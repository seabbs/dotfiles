# Lays out a sanitised review as a GitHub review payload. Each part shows
# one short line and collapses the rest in <details>, so a reader can skim.
#
# Args: $review (sanitised review), $sha, $footer, $mode ("inline" posts
# comments on lines, "plain" folds them into the body when that fails).

def fold($name; $text):
  "<details>\n<summary>" + $name + "</summary>\n\n" + $text
  + "\n\n</details>";

def tag: if .severity == "issue" then "issue"
         elif .severity == "suggestion" then "suggestion"
         else "note" end;

def has_title: (.title // "") != "";

def inline_body:
  if has_title then
    "**" + tag + "** " + .title + "\n\n" + fold("Why and how to fix"; .body)
  else "**" + tag + "** " + .body end;

def plain_item:
  fold(tag + ": " + .path + ":" + (.line | tostring)
       + (if has_title then " " + .title else "" end); .body);

($review.detail // "") as $detail
| ($review.comments // []) as $comments
| ([$review.summary // ""]
   + (if $detail != "" then [fold("Detail"; $detail)] else [] end)
   + (if $mode == "plain" then $comments | map(plain_item) else [] end)
   + [fold("About this review"; $footer)]
  | join("\n\n")) as $body
| {commit_id: $sha, event: "COMMENT", body: $body}
  + if $mode == "plain" then {} else {
      comments: $comments | map({
        path, line, side: "RIGHT", body: inline_body
      })
    } end
