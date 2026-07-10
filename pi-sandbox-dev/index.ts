/**
 * pi-sandbox-dev
 * --------------
 *
 * Auto-builds local Docker images per-project and writes the config that
 * pi-container-sandbox (a separate installed extension) reads at session
 * start. No-op when no project config exists.
 *
 * Key mechanism: pi's extension lifecycle guarantees that async factory
 * functions complete before ANY session_start handler fires. Since
 * pi-container-sandbox reads .pi/agent/sandbox.json in its own
 * session_start handler, our async factory can build the image and write
 * that config file first — guaranteed ordering, regardless of load order.
 *
 * Project config (.pi/sandbox-dev.json):
 *   { "profile": "r", "dockerfile": "r.Dockerfile", "context": "." }
 *
 * Commands:
 *   /sandbox-dev          Show status (profile, image, container)
 *   /sandbox-dev build    Force rebuild the image (--no-cache)
 *   /sandbox-dev doctor   Verify toolchain binaries in the image
 *
 * Image tag scheme (content-addressed):
 *   pi-sandbox-dev-<profile>-<hash8>
 *   Rebuilds ONLY when the Dockerfile contents change.
 */

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	writeFileSync,
	renameSync,
	realpathSync,
} from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// ---------------------------------------------------------------------------
// Extension's own directory (resolve symlinks for dotfiles linking)
// ---------------------------------------------------------------------------

const EXT_DIR = (() => {
	try {
		return dirname(realpathSync(fileURLToPath(import.meta.url)));
	} catch {
		return dirname(fileURLToPath(import.meta.url));
	}
})();

const PROFILES_DIR = join(EXT_DIR, "profiles");

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SandboxDevConfig {
	profile: string;
	dockerfile?: string;
	context?: string;
}

interface SandboxProjectConfig {
	image: string;
	tag: string;
	pinned: boolean;
	lastDigest: string | null;
	lastCheckedAt: number | null;
}

// ---------------------------------------------------------------------------
// Docker helpers
// ---------------------------------------------------------------------------

function dockerAvailable(): boolean {
	const r = spawnSync("docker", ["--version"], { stdio: "ignore" });
	return r.status === 0;
}

function imageExists(imageRef: string): boolean {
	const r = spawnSync("docker", ["image", "inspect", imageRef], { stdio: "ignore" });
	return r.status === 0;
}

function buildImage(
	dockerfilePath: string,
	contextPath: string,
	imageRef: string,
	noCache = false,
): { success: boolean; stderr: string } {
	const args = ["build", "-t", imageRef, "-f", dockerfilePath];
	if (noCache) args.push("--no-cache");
	args.push(contextPath);

	process.stderr.write(`[sandbox-dev] Building image ${imageRef}...\n`);

	const r = spawnSync("docker", args, {
		stdio: ["ignore", "pipe", "pipe"],
	});

	const stderr = r.stderr?.toString() ?? "";

	if (r.status !== 0) {
		return { success: false, stderr };
	}

	process.stderr.write(`[sandbox-dev] Build complete: ${imageRef}\n`);
	return { success: true, stderr };
}

// ---------------------------------------------------------------------------
// Config helpers
// ---------------------------------------------------------------------------

function readSandboxDevConfig(hostCwd: string): SandboxDevConfig | null {
	const configPath = join(hostCwd, ".pi", "sandbox-dev.json");
	if (!existsSync(configPath)) return null;
	try {
		const raw = readFileSync(configPath, "utf-8");
		const parsed = JSON.parse(raw);
		if (!parsed.profile || typeof parsed.profile !== "string") {
			process.stderr.write(
				`[sandbox-dev] Config missing required "profile" field: ${configPath}\n`,
			);
			return null;
		}
		return {
			profile: parsed.profile,
			dockerfile: parsed.dockerfile,
			context: parsed.context,
		};
	} catch (e) {
		process.stderr.write(`[sandbox-dev] Failed to read config: ${e}\n`);
		return null;
	}
}

function resolveDockerfilePath(config: SandboxDevConfig): string {
	const filename = config.dockerfile ?? `${config.profile}.Dockerfile`;
	return join(PROFILES_DIR, filename);
}

function computeImageRef(
	config: SandboxDevConfig,
	dockerfileContents: string,
): { repo: string; tag: string; ref: string } {
	const hash = createHash("sha256").update(dockerfileContents).digest("hex").slice(0, 8);
	const repo = `pi-sandbox-dev-${config.profile}`;
	return { repo, tag: hash, ref: `${repo}:${hash}` };
}

function writeSandboxProjectConfig(hostCwd: string, repo: string, tag: string): void {
	const configPath = join(hostCwd, ".pi", "agent", "sandbox.json");
	const dir = dirname(configPath);
	if (!existsSync(dir)) {
		mkdirSync(dir, { recursive: true });
	}
	const config: SandboxProjectConfig = {
		image: repo,
		tag,
		pinned: true,
		lastDigest: null,
		lastCheckedAt: Date.now(),
	};
	const tmpPath = configPath + ".tmp";
	writeFileSync(tmpPath, JSON.stringify(config, null, 2));
	renameSync(tmpPath, configPath);
}

// ---------------------------------------------------------------------------
// Tool checks for /sandbox-dev doctor
// ---------------------------------------------------------------------------

const PROFILE_TOOLS: Record<string, string[]> = {
	r: ["R --version", "task --version", "git --version", "rg --version"],
	julia: ["julia --version", "task --version", "git --version", "rg --version"],
	generic: ["task --version", "git --version", "rg --version"],
};

function runInImage(
	imageRef: string,
	command: string,
): { exitCode: number | null; stdout: string; stderr: string } {
	const r = spawnSync("docker", ["run", "--rm", imageRef, "sh", "-c", command], {
		stdio: ["ignore", "pipe", "pipe"],
	});
	return {
		exitCode: r.status,
		stdout: r.stdout?.toString() ?? "",
		stderr: r.stderr?.toString() ?? "",
	};
}

// ---------------------------------------------------------------------------
// Shared logic: build + write config (used by factory and /sandbox-dev build)
// ---------------------------------------------------------------------------

function ensureImage(
	config: SandboxDevConfig,
	hostCwd: string,
	force = false,
): { ok: boolean; ref: string; error?: string } {
	const dockerfilePath = resolveDockerfilePath(config);
	if (!existsSync(dockerfilePath)) {
		return {
			ok: false,
			ref: "",
			error: `Dockerfile not found: ${dockerfilePath}\nExpected profile "${config.profile}" Dockerfile in ${PROFILES_DIR}`,
		};
	}

	const dockerfileContents = readFileSync(dockerfilePath, "utf-8");
	const { repo, tag, ref } = computeImageRef(config, dockerfileContents);

	if (!dockerAvailable()) {
		return { ok: false, ref, error: "Docker not available" };
	}

	if (!force && imageExists(ref)) {
		process.stderr.write(`[sandbox-dev] Image up-to-date: ${ref}\n`);
		writeSandboxProjectConfig(hostCwd, repo, tag);
		return { ok: true, ref };
	}

	const contextPath = resolve(hostCwd, config.context ?? ".");
	const result = buildImage(dockerfilePath, contextPath, ref, force);
	if (!result.success) {
		return {
			ok: false,
			ref,
			error: `Docker build failed for profile "${config.profile}".\nImage: ${ref}\nDockerfile: ${dockerfilePath}\n${result.stderr}`,
		};
	}

	writeSandboxProjectConfig(hostCwd, repo, tag);
	process.stderr.write(`[sandbox-dev] Configured pi-container-sandbox to use ${ref}\n`);
	return { ok: true, ref };
}

// ---------------------------------------------------------------------------
// Async factory (runs before all session_start handlers)
// ---------------------------------------------------------------------------

export default async function (pi: ExtensionAPI) {
	const hostCwd = process.cwd();
	const config = readSandboxDevConfig(hostCwd);

	// No-op when no project config
	if (!config) return;

	// Register commands and event handlers (always, even if build fails)
	registerCommands(pi);
	registerEventHandlers(pi);

	// Build image and write config before pi-container-sandbox reads it
	const result = ensureImage(config, hostCwd, false);
	if (!result.ok) {
		throw new Error(`[sandbox-dev] ${result.error}`);
	}
}

// ---------------------------------------------------------------------------
// Command registration
// ---------------------------------------------------------------------------

function registerCommands(pi: ExtensionAPI): void {
	pi.registerCommand("sandbox-dev", {
		description: "Manage pi-sandbox-dev: status, build, doctor",
		handler: async (args, ctx) => {
			const subcommand = (args || "").trim().toLowerCase();

			switch (subcommand) {
				case "":
				case "status":
					await statusCommand(ctx);
					return;
				case "build":
					await buildCommand(ctx);
					return;
				case "doctor":
					await doctorCommand(ctx);
					return;
				default:
					ctx.ui.notify(
						`Unknown subcommand: "${subcommand}". Use: status, build, doctor`,
						"warning",
					);
			}
		},
	});
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function statusCommand(ctx: any): Promise<void> {
	const hostCwd = ctx.cwd as string;
	const config = readSandboxDevConfig(hostCwd);

	if (!config) {
		ctx.ui.notify("No .pi/sandbox-dev.json found — sandbox-dev is inactive", "info");
		return;
	}

	const dockerfilePath = resolveDockerfilePath(config);
	if (!existsSync(dockerfilePath)) {
		ctx.ui.notify(
			`Profile "${config.profile}": Dockerfile not found at ${dockerfilePath}`,
			"warning",
		);
		return;
	}

	const dockerfileContents = readFileSync(dockerfilePath, "utf-8");
	const { ref } = computeImageRef(config, dockerfileContents);

	const built = dockerAvailable() && imageExists(ref);

	// Check for a running pi-container-sandbox container
	let containerRunning = false;
	if (dockerAvailable()) {
		const r = spawnSync(
			"docker",
			["ps", "--filter", "name=pi-sbx-", "--format", "{{.Names}}"],
			{ stdio: ["ignore", "pipe", "pipe"] },
		);
		containerRunning = (r.stdout?.toString() ?? "").trim().length > 0;
	}

	const lines = [
		`Profile: ${config.profile}`,
		`Image: ${ref}`,
		`Image built: ${built ? "yes" : "no"}`,
		`Container running: ${containerRunning ? "yes" : "no"}`,
		`Dockerfile: ${dockerfilePath}`,
	];

	ctx.ui.notify(lines.join("\n"), "info");
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function buildCommand(ctx: any): Promise<void> {
	const hostCwd = ctx.cwd as string;
	const config = readSandboxDevConfig(hostCwd);

	if (!config) {
		ctx.ui.notify("No .pi/sandbox-dev.json found — sandbox-dev is inactive", "info");
		return;
	}

	if (!dockerAvailable()) {
		ctx.ui.notify("Docker not available", "error");
		return;
	}

	ctx.ui.setStatus("sandbox-dev", "Building...");
	ctx.ui.notify(`Force rebuilding image for profile "${config.profile}"`, "info");

	const result = ensureImage(config, hostCwd, true);

	ctx.ui.setStatus("sandbox-dev", undefined);

	if (!result.ok) {
		ctx.ui.notify(`Build failed:\n${result.error?.slice(-800)}`, "error");
		return;
	}

	ctx.ui.notify(`Build complete: ${result.ref}\nConfig updated.`, "info");
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function doctorCommand(ctx: any): Promise<void> {
	const hostCwd = ctx.cwd as string;
	const config = readSandboxDevConfig(hostCwd);

	if (!config) {
		ctx.ui.notify("No .pi/sandbox-dev.json found — sandbox-dev is inactive", "info");
		return;
	}

	if (!dockerAvailable()) {
		ctx.ui.notify("Docker not available", "error");
		return;
	}

	const dockerfilePath = resolveDockerfilePath(config);
	if (!existsSync(dockerfilePath)) {
		ctx.ui.notify(`Dockerfile not found: ${dockerfilePath}`, "error");
		return;
	}

	const dockerfileContents = readFileSync(dockerfilePath, "utf-8");
	const { ref } = computeImageRef(config, dockerfileContents);

	if (!imageExists(ref)) {
		ctx.ui.notify(`Image not built: ${ref}\nRun /sandbox-dev build first.`, "warning");
		return;
	}

	const tools = PROFILE_TOOLS[config.profile] ?? PROFILE_TOOLS.generic;

	ctx.ui.setStatus("sandbox-dev", `Doctor: checking ${tools.length} tools...`);

	const results: string[] = [];
	let allPassed = true;

	for (const toolCmd of tools) {
		const toolName = toolCmd.split(" ")[0];
		const r = runInImage(ref, toolCmd);
		if (r.exitCode === 0) {
			const version = r.stdout.trim().split("\n")[0];
			results.push(`✓ ${toolName}: ${version}`);
		} else {
			allPassed = false;
			results.push(`✗ ${toolName}: failed (exit ${r.exitCode})`);
		}
	}

	ctx.ui.setStatus("sandbox-dev", undefined);

	const summary = allPassed ? "All tools OK" : "Some tools missing";
	ctx.ui.notify(
		`Doctor (${config.profile}): ${summary}\n${results.join("\n")}`,
		allPassed ? "info" : "warning",
	);
}

// ---------------------------------------------------------------------------
// Event handlers
// ---------------------------------------------------------------------------

function registerEventHandlers(pi: ExtensionAPI): void {
	pi.on("session_start", async (_event, ctx) => {
		const config = readSandboxDevConfig(ctx.cwd);
		if (!config) return;

		const dockerfilePath = resolveDockerfilePath(config);
		if (!existsSync(dockerfilePath)) return;

		const dockerfileContents = readFileSync(dockerfilePath, "utf-8");
		const { tag } = computeImageRef(config, dockerfileContents);

		ctx.ui.setStatus("sandbox-dev", `sandbox-dev: ${config.profile} ${tag}`);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		ctx.ui.setStatus("sandbox-dev", undefined);
	});
}
