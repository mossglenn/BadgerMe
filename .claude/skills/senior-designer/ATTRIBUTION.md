# Attribution

This skill is adapted from **senior-designer-skill** by **sshahzaiib**:
https://github.com/sshahzaiib/senior-designer-skill

Licensed under the **MIT License**. The design rules and prose are the original
author's work; cited third-party works (Apple HIG, WCAG, NN/g, Refactoring UI,
etc.) belong to their respective authors and are credited in
`references/evidence-base.md`.

## What was changed in this adaptation

- Converted the GitHub-table frontmatter into standard Agent Skills YAML
  frontmatter (`name`, `description`, `license`). The `description` was trimmed
  to fit the 200-character limit that claude.ai custom-skill uploads enforce;
  the full triggering guidance is preserved verbatim at the top of `SKILL.md`.
- Removed the Claude-Code-specific install instructions (`git clone … ~/.claude/skills/`)
  and README framing, which are not part of the skill itself.
- `references/checklist.md` is the author's original file (43 base items + a
  55-item SwiftUI superset), matching the SKILL.md's `/43` and `/55` scoring.
- The `evals/` and `examples/` folders from the source repo (test prompts and a
  proof-of-concept audit) are not included — they are not needed for the skill
  to function. Fetch them from the source repo if you want them.

The MIT license requires retaining this notice. The full license text is in
`LICENSE` (copy it from the source repo).
