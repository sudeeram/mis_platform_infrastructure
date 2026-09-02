# Repository workflow

- Treat `main` as protected. Never edit, commit, or push directly from `main`.
- Before making a write, confirm the current branch with `git branch --show-current`.
- Start each change from an up-to-date `main`, then create a branch whose name begins with `feature/`, `hotfix/`, or `bugfix/`.
- Keep commits scoped to this repository. A change spanning services requires a matching branch and pull request in every affected repository.
- Run the relevant checks before committing. Push only the working branch and merge it through a pull request.
- Do not bypass or disable the repository hooks. Preserve unrelated user changes already present in the working tree.
