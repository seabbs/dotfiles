# Agents hub setup

Turn the Linux desktop into an SSH-accessible agents hub running persistent
Claude Code sessions, reachable from the laptop over Tailscale.

Shape: one short manual bootstrap to get in and get Claude running, then hand
the rest to an agent on the box.

## Phase 0 — Get into the desktop (manual, one-time)

Both machines are on Tailscale, so the lowest-friction option is Tailscale SSH.
It authenticates over the tailnet via Tailscale identity, so there is no key to
copy and nothing extra to expose.

At the desktop console, once:

```bash
sudo tailscale up --ssh
tailscale status        # note the desktop's MagicDNS name, e.g. "desktop"
```

From the laptop, `ssh <you>@desktop` then works.
Keep the existing key-only OpenSSH (`PasswordAuthentication no`) as the
non-tailnet fallback.

Alternative if sticking to keys: at the desktop console, append the laptop's
`~/.ssh/id_ed25519.pub` to the desktop's `~/.ssh/authorized_keys`.

## Phase 1 — Minimal bootstrap (manual)

SSH in, then:

```bash
# git + curl are usually present; install via apt/dnf if not
git clone https://github.com/seabbs/dotfiles ~/code/seabbs/dotfiles
git -C ~/code/seabbs/dotfiles submodule update --init   # pulls claude/ config
bash ~/code/seabbs/dotfiles/remote/setup.sh             # full env in one shot
```

`remote/setup.sh` installs Linuxbrew then all CLI tools and languages, runs
`scripts/link.sh`, and installs the Linux cron jobs.
This gives zsh/starship, tmux + tmuxinator + config, nvim, R/Julia/Python, gh,
mosh, Claude Code, and the daily `sync-repos` cron.

## Phase 2 — Authenticate (manual, interactive prompts)

```bash
claude          # subscription login: prints a URL -> open on laptop -> paste code
gh auth login   # device flow: paste code at github.com/login/device
```

Both work headless over SSH.
`gh` becomes the git credential helper, so pushes work without a separate key.
Git identity comes from the symlinked `git/config`.

## Phase 3 — Hand the rest to an agent

```bash
tmux new -s agents
claude
```

Handoff prompt:

> Finish configuring this Linux box as my agents hub. Verify `scripts/link.sh`
> symlinked everything, confirm tmux/tmuxinator/nvim/gh/claude all work, check
> the `sync-repos` cron is installed, set up mosh for resilient reconnects, and
> report anything the remote setup skipped vs my Mac. Repo is
> `~/code/seabbs/dotfiles`.

## Phase 4 — Reconnect ergonomics (from the laptop)

- mosh for flaky links (installed by `cli/setup.sh`):

  ```bash
  mosh <you>@desktop -- tmux attach -t agents
  ```

- SSH alias (add to `~/.ssh/config` on the laptop):

  ```
  Host desktop
      HostName desktop            # Tailscale MagicDNS name
      User <you>
  ```

- Keep tmux alive across reboots/logouts:

  ```bash
  loginctl enable-linger <you>
  ```

## What stays manual vs agent-driven

Only Phases 0-2 are hands-on: you cannot reach a box you have no access to, and
the two logins need interactive prompts.
Everything from Phase 3 on is agent-driven.
