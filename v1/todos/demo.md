# Web demo

Extracted from `ideas.md`; tentative alternatives stay there.

- [x] Keep the GitHub Actions build/deploy workflow targeting pushes to main and the Pages Actions publishing source.
- [x] Build the updated demo and verify startup and gameplay in a browser without special response headers.

Implementation notes: Pages uses GitHub Actions and the existing workflow deploys pushes to main. The updated single-threaded Web export builds and passes Chrome startup/gameplay checks under a subdirectory without cross-origin isolation headers. All 28 headless integration suites and both rendered suites pass. A push containing the changes triggers publication; no deployment was manually started during this iteration.
