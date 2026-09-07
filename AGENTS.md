# Repository workflow

- Treat `develop` and `main` as protected. Never edit, commit, or push directly from either branch.
- Before making a write, confirm the current branch with `git branch --show-current`.
- Start `feature/*` and `bugfix/*` work from `develop` and open the pull request back to `develop`. Start urgent `hotfix/*` work from `main`, open it to `main`, then merge `main` back into `develop`.
- Keep commits scoped to this repository. A change spanning services requires a matching branch and pull request in every affected repository.
- Run the relevant checks before committing. Push only the working branch and merge it through a pull request.
- Do not bypass or disable the repository hooks. Preserve unrelated user changes already present in the working tree.
