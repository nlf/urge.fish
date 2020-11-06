# urge

A minimalist, high-performance fish prompt with async git dirty checks that just work.

Forked from the excellent [lucid.fish](https://github.com/mattgreen/lucid.fish).

## Features

### Changes in urge

* Nothing, yet

### Inherited from lucid

* Classy, minimal left prompt that surfaces only actionable information
* Asynchronous git dirty state prevents prompt-induced lag even on [massive repositories](https://github.com/llvm/llvm-project)
* Shows current git branch/detached HEAD commit, action (if any), and dirty state
* Restrained use of color and Unicode symbols
* Single file, well-commented, zero-dependency implementation

## Requirements

* fish 3.1

## Installation

Install with fisher:

    $ fisher add nlf/urge.fish

**Back up your existing prompt before doing this!**

Or install it manually. It's only one file, after all.

## Performance

urge fetches most git information synchronously. This minimizes the amount of flicker induced by prompt redraws, which can be distracting. This initial time encompasses:

1. getting the git working directory
2. retrieving the current branch
3. figuring out the current action (merge, rebase)
4. starting the async dirty check

This information is memoized to avoid re-computation during prompt redraws, which occur upon completion of the git dirty check, or window resizes.

## Customization

* `urge_dirty_indicator`: displayed when a repository is dirty. Default: `•`
* `urge_clean_indicator`: displayed when a repository is clean. Should be at least as long as `urge_dirty_indicator` to work around a fish bug. Default: ` ` (a space)
* `urge_cwd_color`: color used for current working directory. Default: `green`
* `urge_git_color`: color used for git information. Default: `blue`

## Design

Each prompt invocation launches a background job responsible for checking dirty status. If the previous job did not complete, it is killed prior to starting a new job. The dirty check job relays the dirty status back to the main shell via an exit code. This works because there's only three distinct states that can result from a dirty check: dirty, not dirty, or error. Systems programming FTW!

After launching the job, the parent process immediately registers a completion handler for the job. In there, we scoop up the exit status, then update the prompt based on what was found.

The rest is book-keeping and careful coding. There may be a few more opportunities for optimization. Send a PR if you find any!

## Known Issues

* fish has a bug involving multi-line prompts not being redrawn correctly. You usually see this when invoking `fzf`.
* urge uses a background job to asynchronously fetch dirty status. If you try to exit while a dirty status has not completed, fish will warn you it is still running. Unfortunately, urge is not able to `disown` the job because it needs to collect the exit status from it.

## License
MIT
