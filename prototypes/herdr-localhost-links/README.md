# Herdr localhost links

A minimal Herdr plugin that sends Ctrl-clicked HTTP(S) loopback URLs through the owning Herdr server's `xdg-open`. Herdr supplies clicked URLs in `HERDR_PLUGIN_CLICKED_URL`; the manifest action needs no positional URL argument. The server replaces only the validated loopback host span, preserving scheme case, port spelling, path/query/fragment bytes (including empty `?` and `#` delimiters), and invokes the opener with an argv array (never a shell). Non-loopback URLs pass through unchanged without invoking target inference. The manifest regex accepts HTTP(S) schemes and loopback host spellings case-insensitively.

## Target inference and limits

Precedence for a loopback URL:

1. `HERDR_LOCALHOST_LINK_HOST` (explicit hostname or IP override).
2. If `herdr-client-connection` is in the action's `PATH`, invoke it once to determine the active client dynamically. A successful empty result means local client: inherited `SSH_CONNECTION` is removed from the child opener environment. A successful value is used both as the target evidence and to set the child opener's `SSH_CONNECTION`. The parent process environment is never mutated. Without an explicit target, helper failure is an error and does not fall back to potentially stale SSH state. With an explicit target, the handler proceeds using the original child environment and reports that SSH context could not be refreshed.
3. If the helper is unavailable on Linux, use SSH evidence (`SSH_CONNECTION`, `SSH_CLIENT`, or `SSH_TTY`); the third `SSH_CONNECTION` field (server-side address) is preferred if it is a valid non-loopback, non-unspecified, non-multicast IP. On macOS, inherited SSH-only evidence with no active-client helper is ambiguous and fails closed; use the explicit override or make the active-client helper available.
4. Otherwise a valid `HERDR_LOCALHOST_LINK_FQDN`, `HOSTNAME`, or `FQDN` when positive remote evidence exists.
5. Without remote evidence, leave the loopback URL unchanged. If remote context exists but no usable target is available, print an error rather than invent a target.

The helper identifies the active client by most recent input atime (see `~/.local/bin/herdr-client-connection`); simultaneous clients or platform limitations can make selection ambiguous. Its behavior depends on the current server-side Herdr process environment and filesystem. Linux fallback from SSH environment is best-effort: it may be stale and its server-side address or hostname may not be reachable from the Mac. A hostname is used only with positive remote evidence; hostname text is never used to guess the server platform. IPv6 explicit targets are accepted and bracketed in the rewritten URL.

The first `SSH_CONNECTION` field is the connecting client's address and is deliberately not used as the server host. This inference is best-effort only: server interface addresses may be private, stale, NATed, unroutable from the Mac, or unrelated to a currently attached client. A hostname may resolve differently from the Mac. Diagnostics identify the selected evidence and explicitly mark inferred/override targets as reachability-unverified. An operator can set the explicit override in the server environment when automatic identity is wrong. When available, `herdr-client-connection` queries the active attached client's origin; the plugin does not query DNS, routes, or a remote machine.

The per-machine `sync_herdr_ssh_connection` helper in `~/.config/fish/functions/sync_herdr_ssh_connection.fish` refreshes SSH origin context, but does not establish a browser-reachable hostname. When `herdr-client-connection` is available, the plugin uses it instead of trusting persisted SSH_CONNECTION. If it is absent, Linux fallback environment may be stale; macOS fails closed for SSH-only inherited evidence because it cannot distinguish a current remote attach from a stale value.

A disposable Herdr `pane.link.activate` integration check validated manifest dispatch, clicked-URL environment delivery, helper-derived target evidence, and the exact rewritten argument to a recording `xdg-open`. Unit tests additionally verify that the child opener receives the active SSH_CONNECTION or no SSH_CONNECTION for a successful-empty local result. This does not establish that the existing Mac `xdg-open` override works over a real remote Herdr transport; that boundary requires testing against the actual per-machine opener and transport.

## Verification status

- All 24 unit tests passed, and independent review found no remaining issues.
- In a disposable Herdr session on desktop, the real active-client helper inferred the server address without an override. `pane.link.activate` dispatched the handler and reached the actual `xdg-open` forwarding command.
- Mac browser delivery remains blocked: the opener's `ssh macbook open` command exited 255 with `Too many authentication failures`; no test-page request was observed.
- Actual Ctrl-click input, tracked-machine mode, and `herdr --remote` remain unverified. Temporary sessions, test servers, and remote files were cleaned up. Nothing was installed into live sessions.

This directory is excluded from `chezmoi apply`; linking the plugin remains manual.

## Install manually (not performed)

From the checked-out repository root, on each Herdr server:

```sh
herdr plugin link "$PWD/prototypes/herdr-localhost-links"
herdr plugin list
herdr plugin action list --plugin local.herdr-localhost-links
```

Plugin actions execute on their owning Herdr server. Ensure `python3` and the intended `xdg-open` are in that server process's `PATH`; no installation or live-session changes are performed by this prototype. In each target server environment, configure `HERDR_LOCALHOST_LINK_HOST` only if best-effort server identity is unsuitable.

## Tests

```sh
python3 -m unittest discover -s prototypes/herdr-localhost-links -v
```

Tests use only Python's standard library, temporary fake helper/opener executables, and no live Herdr helper. An isolated visual Herdr session and recording opener were used for the API-level integration check; no live/default session was touched.

## References

- [Herdr v0.9.3 plugin documentation](https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/plugins.mdx#link-handlers) — link-handler patterns, action dispatch, and clicked-URL environment.
- [`herdr-client-connection`](../../dot_local/bin/executable_herdr-client-connection) — existing active-client SSH-context detection.
- [`sync_herdr_ssh_connection.fish`](../../dot_config/fish/functions/sync_herdr_ssh_connection.fish) — existing connection-origin refresh; not a remote hostname resolver.
