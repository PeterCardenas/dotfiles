#!/usr/bin/env python3
"""Rewrite loopback HTTP(S) links for the remote Herdr server and open them."""

from dataclasses import dataclass
import ipaddress
import os
import re
import shutil
import subprocess
import sys
from urllib.parse import urlsplit


@dataclass(frozen=True)
class TargetResolution:
    host: str | None
    evidence: str
    opener_env: dict[str, str]
    error: str | None = None
    warning: str | None = None


def valid_host(value):
    if not value or value != value.strip() or any(character in value for character in "/\\@?#[]%"):
        return False
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        normalized = value.lower().rstrip(".")
        if normalized == "localhost" or normalized.endswith(".localhost"):
            return False
        return bool(re.fullmatch(r"(?=.{1,253}\Z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.?", value))
    mapped_loopback = address.version == 6 and address.ipv4_mapped is not None and address.ipv4_mapped.is_loopback
    return not (address.is_loopback or address.is_unspecified or address.is_multicast or mapped_loopback)


def resolve_target(env, platform=sys.platform):
    opener_env = dict(env)
    explicit = env.get("HERDR_LOCALHOST_LINK_HOST")
    if explicit and not valid_host(explicit):
        raise ValueError("HERDR_LOCALHOST_LINK_HOST is not a valid hostname or IP address")
    connection_value = env.get("SSH_CONNECTION", "")
    helper = shutil.which("herdr-client-connection", path=env.get("PATH", ""))
    remote = False
    evidence = "no SSH/remote evidence"
    if helper:
        try:
            result = subprocess.run([helper], env=env, capture_output=True, text=True, check=False, timeout=2)
        except subprocess.TimeoutExpired as error:
            if explicit:
                warning = "herdr-client-connection timed out; SSH context could not refresh, opener SSH environment left unchanged"
                return TargetResolution(explicit, "HERDR_LOCALHOST_LINK_HOST (explicit; reachability unverified)", opener_env, warning=warning)
            raise ValueError("herdr-client-connection timed out after 2 seconds") from error
        except OSError as error:
            if explicit:
                warning = f"herdr-client-connection could not run; SSH context could not refresh ({error}), opener SSH environment left unchanged"
                return TargetResolution(explicit, "HERDR_LOCALHOST_LINK_HOST (explicit; reachability unverified)", opener_env, warning=warning)
            raise ValueError(f"herdr-client-connection could not run: {error}") from error
        if result.returncode != 0:
            if explicit:
                warning = "herdr-client-connection failed; SSH context could not refresh, opener SSH environment left unchanged"
                return TargetResolution(explicit, "HERDR_LOCALHOST_LINK_HOST (explicit; reachability unverified)", opener_env, warning=warning)
            raise ValueError("herdr-client-connection failed; refusing possibly stale SSH environment")
        # A successful empty result identifies local client and overrides inherited server env.
        connection_value = result.stdout.strip()
        if connection_value:
            remote = True
            opener_env["SSH_CONNECTION"] = connection_value
            evidence = "active-client SSH_CONNECTION server-side address (best effort; reachability unverified)"
        else:
            opener_env.pop("SSH_CONNECTION", None)
            evidence = "herdr-client-connection reports local client"
    else:
        remote = any(env.get(name) for name in ("SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"))
        evidence = "SSH_CONNECTION server-side address (best effort; reachability unverified)"
        if explicit:
            warning = "herdr-client-connection unavailable; SSH context could not refresh, opener SSH environment left unchanged"
            return TargetResolution(explicit, "HERDR_LOCALHOST_LINK_HOST (explicit; reachability unverified)", opener_env, warning=warning)

    if explicit:
        return TargetResolution(explicit, "HERDR_LOCALHOST_LINK_HOST (explicit; reachability unverified)", opener_env)

    if not helper and remote and platform == "darwin":
        return TargetResolution(None, evidence, opener_env, "active-client helper unavailable on macOS; inherited SSH context is ambiguous; set HERDR_LOCALHOST_LINK_HOST")

    connection = connection_value.split()
    if len(connection) == 4:
        try:
            address = ipaddress.ip_address(connection[2])
            if valid_host(str(address)):
                return TargetResolution(str(address), evidence, opener_env)
        except ValueError:
            pass
    if remote:
        for name in ("HERDR_LOCALHOST_LINK_FQDN", "HOSTNAME", "FQDN"):
            value = env.get(name, "")
            if valid_host(value):
                return TargetResolution(value, f"{name} (best effort; reachability unverified)", opener_env)
        return TargetResolution(None, evidence, opener_env, "remote context detected but cannot infer a valid target; set HERDR_LOCALHOST_LINK_HOST")
    return TargetResolution(None, evidence, opener_env)


def target_host(env, platform=sys.platform):
    resolution = resolve_target(env, platform)
    if resolution.error:
        raise ValueError(resolution.error)
    return resolution.host, resolution.evidence


def parse_url(url):
    if not isinstance(url, str) or not url:
        raise ValueError("missing URL")
    try:
        parts = urlsplit(url)
        if parts.scheme.lower() not in ("http", "https") or not parts.netloc:
            raise ValueError("only absolute HTTP(S) URLs are supported")
        host = parts.hostname
        _ = parts.port
    except ValueError as error:
        raise ValueError(f"invalid URL: {error}") from error
    if host is None:
        raise ValueError("invalid URL: missing host")
    loopback = host.lower().rstrip(".") in ("localhost", "127.0.0.1", "::1")
    if loopback and (parts.username is not None or parts.password is not None):
        raise ValueError("loopback URLs containing credentials are not rewritten")
    return parts, loopback


def rewrite_url(url, env=None, *, platform=sys.platform, resolution=None, parsed=None):
    parsed_url = parse_url(url) if parsed is None else parsed
    parts, loopback = parsed_url
    if not loopback:
        return url
    environment = os.environ if env is None else env
    target = resolution if resolution is not None else resolve_target(environment, platform)
    if target.error:
        raise ValueError(target.error)
    if target.host is None:
        return url
    scheme_match = re.match(r"(?i)https?://", url)
    if scheme_match is None:
        raise ValueError("only absolute HTTP(S) URLs are supported")
    authority_start = scheme_match.end()
    authority_end = min((index for index in (url.find("/", authority_start), url.find("?", authority_start), url.find("#", authority_start)) if index >= 0), default=len(url))
    authority = url[authority_start:authority_end]
    host_start = authority_start + (authority.rfind("@") + 1)
    if url[host_start:host_start + 1] == "[":
        host_end = url.find("]", host_start) + 1
    else:
        host_end = url.find(":", host_start)
        if host_end < 0 or host_end > authority_end:
            host_end = authority_end
    replacement = f"[{target.host}]" if ":" in target.host else target.host
    rewritten = url[:host_start] + replacement + url[host_end:]
    print(f"herdr-localhost-links: target {target.host}; evidence: {target.evidence}", file=sys.stderr)
    return rewritten


def main(argv=None):
    arguments = sys.argv[1:] if argv is None else argv
    if len(arguments) > 1:
        print("usage: link_handler.py [URL]", file=sys.stderr)
        return 2
    url = arguments[0] if arguments else os.environ.get("HERDR_PLUGIN_CLICKED_URL", "")
    try:
        if not url:
            raise ValueError("missing URL; HERDR_PLUGIN_CLICKED_URL is empty")
        environment = os.environ.copy()
        parsed = parse_url(url)
        if parsed[1]:
            target = resolve_target(environment)
            if target.warning:
                print(f"herdr-localhost-links: {target.warning}", file=sys.stderr)
            url = rewrite_url(url, environment, resolution=target, parsed=parsed)
        else:
            target = TargetResolution(None, "non-loopback URL", environment)
    except ValueError as error:
        print(f"herdr-localhost-links: {error}", file=sys.stderr)
        return 2
    opener = shutil.which("xdg-open", path=environment.get("PATH", ""))
    if opener is None:
        print("herdr-localhost-links: xdg-open not found in server PATH", file=sys.stderr)
        return 127
    try:
        return subprocess.run([opener, url], env=target.opener_env, check=False).returncode
    except OSError as error:
        print(f"herdr-localhost-links: cannot execute xdg-open: {error}", file=sys.stderr)
        return 127


if __name__ == "__main__":
    raise SystemExit(main())
