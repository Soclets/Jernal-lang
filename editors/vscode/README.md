# Jernal for VS Code

Syntax highlighting for Jernal (`.jern`) and its manifest (`Journey.siml`, `Journey.lock`), with `//` comments,
`:`-to-`end` indentation, and bracket and quote pairs.

To build and install it:

```
npx --yes @vscode/vsce package --allow-missing-repository --skip-license
code --install-extension jernal-0.0.1.vsix
```
