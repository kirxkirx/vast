# Claude Code Instructions for VaST

## Development Environment

- The main development repository is at `/home/kirx/vast_test/vast`.
- To investigate test failures or trace the origin of bugs (e.g., using `git bisect`), create a separate test copy of the repository in `/tmp/vast` by cloning from GitHub (`git clone https://github.com/kirxkirx/vast.git /tmp/vast`). Run builds and tests there to avoid disturbing the development directory. Download any needed test data into the `/tmp/vast` directory.

## Related Repositories

VaST (variable star and transient search code in this repository) is frequently used for transient search as part of a pipeline together with two companion repositories:

- `/tmp/unmw` - server-side wrapper scripts that ingest an uploaded archive containing new images, run VaST to compare the new images against the reference images, and then manage the output HTML pages, producing a summary log and combined lists of transients from individual single-field results.
- `/tmp/astrocam-go` - client-side code that creates these image archives at the telescope and uploads them to the server running unmw + VaST.

Data flow: `astrocam-go` (acquires/packages images) -> uploads to server -> `unmw` (ingests archive, invokes VaST) -> VaST (does the actual transient detection) -> `unmw` (collates results into HTML/summary).

Compatibility rule: changes in VaST must not break compatibility with `unmw` or `astrocam-go`. Coordinated changes across multiple repositories are allowed when a breaking change is genuinely necessary, but in that case the dependent repositories must be updated in step.

## Git Workflow

- Do not make git commits yourself. After successfully modifying files, run `git add` on the changed files, then suggest a one-line very short commit message for the user to use. Commit messages must ALWAYS be a single line - no multi-line bodies, no blank line + paragraph; if a longer rationale is needed, put it in the chat reply, not the commit message.
- `.claude/CLAUDE.md`, `.claude/notes.md` and the design docs in `.claude/` are tracked in git so Claude can work on any machine that clones the repository. Stage them when they change. Never stage `.claude/settings.local.json`, `.claude/projects/` or editor backup files (`*~`) - they are per-machine.

## Portability Requirements

VaST should compile with gcc 4.1 and should mostly work on legacy Scientific Linux 5.6 (the reference system). This will not always be possible, especially for the Python modules, but the goal is to have at least core functionality compatible with the legacy system.

Additional platform requirements:
- Alpine Linux using busybox and musl (assuming bash is also installed)
- FreeBSD
- Latest macOS

The core functionality of VaST should be available on all of the above platforms. Whenever a feature incompatible with these portability requirements is introduced, we must carefully consider the tradeoffs between the new feature for modern systems and breaking backward compatibility.

## Building

- Always recompile VaST fully with `make`. Never compile individual components separately - it usually does not work due to complex dependencies in the build system.
- Never use `make -j` - parallel builds do not work for this project. Always use plain `make`.

## Code Validation

- Always run syntax checks on modified C files before a full build to catch errors quickly:
  ```bash
  gcc -fsyntax-only -I src src/filename.c
  ```
  For example: `gcc -fsyntax-only -I src src/solve_plate_with_UCAC5.c`

- Always run shellcheck on modified bash scripts to catch common issues:
  ```bash
  shellcheck path/to/script.sh
  ```
  For example: `shellcheck util/transients/report_transient.sh`

  Note: Not all shellcheck warnings need to be fixed - use judgment for style suggestions (SC2181) and intentional patterns like unused variables in `read` loops.

- Always syntax-check GitHub Actions workflow YAML files after modifying them:
  ```bash
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/filename.yml'))"
  ```
  For example: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build_and_test_ubuntu.yml'))"`

## C Coding Style

- All variables must be declared at the start of a function, before any executable statements.
- Never declare variables inside a loop, inside a `{ }` block scope, or in the middle of a function body. Move them to the top of the enclosing function.
- Do not use `{ }` block scopes solely to introduce new variable declarations mid-function. Instead, declare those variables at the function's top alongside the others.
- This is required for compatibility with older C standards (C89/C90), gcc 4.1, and uniform code style across the project.
- Use C++ style comments (`//`) for actual code comments. Use C style comments (`/* */`) only for commenting out large blocks of code. This convention makes it easy to disable a chunk of code with `/* */` without conflicting with inline comments. Never remove or convert existing `//` comments to `/* */`.

## Text and Encoding

- Never use non-ASCII characters in code, comments, documentation, or text files. Use only plain ASCII throughout (e.g., write "degrees C" or "deg" instead of the degree symbol).

## Plotting Style

- Never draw a background grid on plots. No `ax.grid(...)` in matplotlib, no `set grid` in gnuplot, and the equivalent in any other plotting tool. This applies to all diagnostic plots produced by VaST code and to any one-off analysis plots.

## Terminology

- Do not use ad-hoc step-numbering labels like "Phase 1" / "Phase 2" / "Step A" in chat replies, commit messages, code comments, or variable names. They are context-dependent and only meaningful inside one specific function or one specific conversation turn - outside that scope nobody can tell what they refer to.
- Refer to what the step actually does (e.g., "parallel plate-solving step", "forced-photometry measurement loop", "rsync of the working copy") rather than its ordinal position.

## Maintenance Notes

- Check and update `.claude/notes.md` for lessons learned about what works and what doesn't when maintaining VaST code. Add new notes as you discover things.

## Testing and Cleanup

- Use `util/clean_data.sh` to clean previous VaST run's data before running new tests.
- **Never run `util/examples/test_vast.sh`** - it takes many hours. It does not accept command line arguments and must not be modified to do so. To test individual features, run the specific standalone test script (e.g., `util/examples/test_NMW_TexasTech_Gem03Q1b1x1.sh`) or test manually.
- **Never run `./vast` directly** - it opens a GUI (pgplot) window. Use test scripts or headless tools instead.
