#!/usr/bin/env python3
"""
Shared tenant-wide Azure inventory helpers: CLI auth, Resource Graph pagination,
and cached subscription → management group mapping (read-only via ARG).
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

CACHE_VERSION = 3
DEFAULT_CACHE_PATH = Path.home() / ".cache" / "az-subscription-mg-map.json"
LEGACY_CACHE_PATH = Path.home() / ".cache" / "aks-subscription-mg-map.json"
ARG_PAGE_SIZE = 1000

SUBSCRIPTION_ARG_QUERY = """
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions'
| extend subscriptionId=tolower(tostring(subscriptionId))
| extend ancChain=iif(
    isnull(properties.managementGroupAncestorsChain),
    dynamic([]),
    todynamic(properties.managementGroupAncestorsChain))
| extend directMgId=tostring(properties.managementGroupId)
| project subscriptionId, subscriptionName=name, ancChain, directMgId
""".strip()

MANAGEMENT_GROUP_ARG_QUERY = """
ResourceContainers
| where type =~ 'microsoft.management/managementgroups'
| project
    id=name,
    displayName=tostring(properties.displayName),
    parentId=tostring(properties.details.parent.name)
""".strip()


class AzCliError(RuntimeError):
    pass


class AzContext:
    tenant_id: str
    user_name: str
    subscription_id: str
    subscription_name: str

    def __init__(
        self,
        *,
        tenant_id: str,
        user_name: str,
        subscription_id: str,
        subscription_name: str,
    ) -> None:
        self.tenant_id = tenant_id
        self.user_name = user_name
        self.subscription_id = subscription_id
        self.subscription_name = subscription_name


def log(message: str, *, quiet: bool) -> None:
    if not quiet:
        print(message, file=sys.stderr)


def run_az(args: list[str], *, check: bool = True) -> str:
    cmd = ["az", *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise AzCliError(detail or f"az {' '.join(args)} failed")
    return result.stdout


def ensure_az_login(*, quiet: bool) -> None:
    try:
        run_az(["account", "show"], check=True)
    except AzCliError:
        log("Not logged into Azure. Running az login (tenant-wide; no subscription required)...", quiet=quiet)
        subprocess.run(["az", "login"], check=True)


def get_az_context() -> AzContext:
    payload = json.loads(run_az(["account", "show", "-o", "json"]))
    tenant_id = str(payload.get("tenantId") or payload.get("homeTenantId") or "").strip()
    if not tenant_id:
        raise AzCliError("Could not determine tenant id from az account show")

    user = payload.get("user") or {}
    user_name = str(user.get("name") or user.get("type") or "unknown").strip()

    return AzContext(
        tenant_id=tenant_id,
        user_name=user_name,
        subscription_id=str(payload.get("id") or "").strip(),
        subscription_name=str(payload.get("name") or "").strip(),
    )


def log_az_context(ctx: AzContext, *, quiet: bool) -> None:
    log(f"Azure CLI context: tenant={ctx.tenant_id} user={ctx.user_name}", quiet=quiet)
    if ctx.subscription_name:
        log(
            f"  Default subscription (CLI context only): {ctx.subscription_name} ({ctx.subscription_id})",
            quiet=quiet,
        )


def graph_query_all(query: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    skip_token: str | None = None

    while True:
        args = [
            "graph",
            "query",
            "-q",
            query,
            "--allow-partial-scopes",
            "--first",
            str(ARG_PAGE_SIZE),
            "-o",
            "json",
        ]
        if skip_token:
            args.extend(["--skip-token", skip_token])

        payload = json.loads(run_az(args))
        rows.extend(payload.get("data") or [])

        skip_token = payload.get("$skipToken") or payload.get("skip_token")
        if not skip_token:
            break

    return rows


def management_group_display_map(groups: list[dict[str, str]]) -> dict[str, str]:
    display: dict[str, str] = {}
    for group in groups:
        mg_id = group["id"]
        display[mg_id] = group["displayName"]
        display[mg_id.lower()] = group["displayName"]
    return display


def normalize_management_group_chain(
    anc_chain: Any,
    direct_mg_id: str,
    mg_display: dict[str, str],
) -> list[dict[str, str]]:
    chain: list[dict[str, str]] = []
    if isinstance(anc_chain, list):
        for item in anc_chain:
            if not isinstance(item, dict):
                continue
            mg_id = str(item.get("name") or "").strip()
            if not mg_id:
                continue
            display = str(item.get("displayName") or "").strip()
            chain.append(
                {
                    "id": mg_id,
                    "displayName": display or mg_display.get(mg_id, mg_display.get(mg_id.lower(), mg_id)),
                }
            )

    direct_mg_id = str(direct_mg_id or "").strip()
    if direct_mg_id:
        last_id = chain[-1]["id"].lower() if chain else ""
        if last_id != direct_mg_id.lower():
            chain.append(
                {
                    "id": direct_mg_id,
                    "displayName": mg_display.get(
                        direct_mg_id, mg_display.get(direct_mg_id.lower(), direct_mg_id)
                    ),
                }
            )

    deduped: list[dict[str, str]] = []
    for item in chain:
        if deduped and deduped[-1]["id"].lower() == item["id"].lower():
            if not deduped[-1]["displayName"] and item["displayName"]:
                deduped[-1]["displayName"] = item["displayName"]
            continue
        deduped.append(item)
    return deduped


def format_management_group_hierarchy(
    chain: list[dict[str, str]],
    mg_display: dict[str, str],
) -> tuple[str, str, list[str]]:
    if not chain:
        return "", "", []

    labels: list[str] = []
    mg_ids: list[str] = []
    for item in reversed(chain):
        mg_id = item["id"]
        label = item["displayName"] or mg_display.get(mg_id, mg_display.get(mg_id.lower(), mg_id))
        labels.append(label)
        mg_ids.append(mg_id)

    return " -> ".join(labels), chain[-1]["id"], mg_ids


def fetch_management_groups_from_arg() -> list[dict[str, str]]:
    groups: list[dict[str, str]] = []
    for row in graph_query_all(MANAGEMENT_GROUP_ARG_QUERY):
        mg_id = str(row.get("id") or "").strip()
        if not mg_id:
            continue
        groups.append(
            {
                "id": mg_id,
                "displayName": str(row.get("displayName") or mg_id),
                "parentId": str(row.get("parentId") or ""),
            }
        )
    return groups


def build_subscription_map_from_arg(
    mg_display: dict[str, str],
) -> dict[str, dict[str, str]]:
    subscription_map: dict[str, dict[str, str]] = {}
    for row in graph_query_all(SUBSCRIPTION_ARG_QUERY):
        sub_id = str(row.get("subscriptionId") or "").strip().lower()
        if not sub_id:
            continue
        chain = normalize_management_group_chain(
            row.get("ancChain"),
            str(row.get("directMgId") or ""),
            mg_display,
        )
        hierarchy, direct_mg_id, mg_ids = format_management_group_hierarchy(chain, mg_display)
        subscription_map[sub_id] = {
            "subscriptionName": str(row.get("subscriptionName") or sub_id),
            "managementGroup": hierarchy,
            "managementGroupId": direct_mg_id,
            "managementGroupIds": mg_ids,
        }
    return subscription_map


def list_enabled_subscriptions(tenant_id: str) -> dict[str, str]:
    payload = json.loads(run_az(["account", "list", "-o", "json"]))
    subs: dict[str, str] = {}
    for item in payload:
        if str(item.get("tenantId") or "").strip().lower() != tenant_id.lower():
            continue
        if str(item.get("state") or "").lower() != "enabled":
            continue
        sub_id = str(item.get("id") or "").strip().lower()
        if sub_id:
            subs[sub_id] = str(item.get("name") or sub_id)
    return subs


def fill_missing_subscriptions(
    subscription_map: dict[str, dict[str, str]],
    tenant_id: str,
    *,
    quiet: bool,
) -> dict[str, dict[str, str]]:
    enabled = list_enabled_subscriptions(tenant_id)
    missing = [sid for sid in enabled if sid not in subscription_map]
    if not missing:
        return subscription_map

    log(
        f"Adding {len(missing)} subscription(s) visible to CLI but absent from Resource Graph...",
        quiet=quiet,
    )
    for sub_id in missing:
        subscription_map[sub_id] = {
            "subscriptionName": enabled[sub_id],
            "managementGroup": "",
            "managementGroupId": "",
            "managementGroupIds": [],
        }
    return subscription_map


def build_cache(ctx: AzContext, *, quiet: bool) -> dict[str, Any]:
    log("Building subscription map via Resource Graph (read-only)...", quiet=quiet)
    management_groups = fetch_management_groups_from_arg()
    mg_display = management_group_display_map(management_groups)
    subscription_map = build_subscription_map_from_arg(mg_display)
    subscription_map = fill_missing_subscriptions(
        subscription_map, ctx.tenant_id, quiet=quiet
    )

    return {
        "version": CACHE_VERSION,
        "tenantId": ctx.tenant_id,
        "builtBy": ctx.user_name,
        "builtAt": datetime.now(timezone.utc).isoformat(),
        "managementGroups": management_groups,
        "subscriptions": subscription_map,
    }


def cache_matches_context(cache: dict[str, Any], ctx: AzContext) -> bool:
    if cache.get("version") != CACHE_VERSION:
        return False
    if cache.get("tenantId") != ctx.tenant_id:
        return False
    cached_user = str(cache.get("builtBy") or "").strip()
    if cached_user and cached_user != ctx.user_name:
        return False
    return bool(cache.get("subscriptions"))


def load_cache(cache_path: Path) -> dict[str, Any] | None:
    for path in (cache_path, LEGACY_CACHE_PATH):
        if not path.is_file():
            continue
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
    return None


def save_cache(cache_path: Path, payload: dict[str, Any]) -> None:
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def get_subscription_map(
    ctx: AzContext, *, cache_path: Path, refresh: bool, quiet: bool
) -> dict[str, dict[str, str]]:
    cache = None if refresh else load_cache(cache_path)

    if cache and cache_matches_context(cache, ctx):
        log(
            f"Loaded subscription map from cache: {cache_path} "
            f"(tenant={ctx.tenant_id}, user={ctx.user_name})",
            quiet=quiet,
        )
        return cache["subscriptions"]

    if cache and cache.get("tenantId") != ctx.tenant_id:
        log(
            f"Cache tenant mismatch (cached={cache.get('tenantId')} "
            f"current={ctx.tenant_id}); rebuilding...",
            quiet=quiet,
        )
    elif cache and cache.get("builtBy") and cache.get("builtBy") != ctx.user_name:
        log(
            f"Cache user mismatch (cached={cache.get('builtBy')} "
            f"current={ctx.user_name}); rebuilding...",
            quiet=quiet,
        )
    elif not cache:
        log(f"Cache not found; building subscription map at {cache_path}", quiet=quiet)
    else:
        log("Refreshing subscription map...", quiet=quiet)

    payload = build_cache(ctx, quiet=quiet)
    save_cache(cache_path, payload)
    log(f"Saved subscription map to {cache_path}", quiet=quiet)
    return payload["subscriptions"]


def matches_management_group_filter(
    sub_meta: dict[str, Any], mg_filter: str | None
) -> bool:
    if not mg_filter:
        return True
    mg_filter_lower = mg_filter.lower()
    mg_path = str(sub_meta.get("managementGroup", "")).lower()
    mg_ids = [str(x).lower() for x in sub_meta.get("managementGroupIds", [])]
    direct_mg = str(sub_meta.get("managementGroupId", "")).lower()
    return (
        mg_filter_lower in mg_path
        or mg_filter_lower in direct_mg
        or any(mg_filter_lower in mg_id for mg_id in mg_ids)
    )


ID_OUTPUT_COLUMNS = ["managementGroupName", "resourceId"]


def format_id_output(rows: list[dict[str, str]], fmt: str) -> str:
    """Minimal output: management group hierarchy and full ARM resource id."""
    slim = [
        {
            "managementGroupName": row.get("managementGroupName", ""),
            "resourceId": row.get("resourceId", ""),
        }
        for row in rows
    ]
    if fmt == "json":
        return json.dumps(slim, indent=2)
    if fmt == "tsv":
        lines = ["\t".join(ID_OUTPUT_COLUMNS)]
        for row in slim:
            lines.append("\t".join(row[col] for col in ID_OUTPUT_COLUMNS))
        return "\n".join(lines)
    if fmt == "table":
        mg_width = max(
            [len("Management Group")]
            + [len(row["managementGroupName"]) for row in slim]
        )
        mg_width = min(max(mg_width, 20), 120)
        lines = [f"{'Management Group':<{mg_width}}  Resource Id", f"{'-' * mg_width}  -----------"]
        for row in slim:
            mg_label = row["managementGroupName"]
            if len(mg_label) > mg_width:
                mg_label = mg_label[: mg_width - 3] + "..."
            lines.append(f"{mg_label:<{mg_width}}  {row['resourceId']}")
        return "\n".join(lines)
    raise ValueError(f"Unsupported format: {fmt}")
