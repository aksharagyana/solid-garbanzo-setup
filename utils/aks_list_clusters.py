#!/usr/bin/env python3
"""
List AKS clusters tenant-wide with subscription and management group enrichment.

Subscription → management group mapping is built via Azure Resource Graph (read-only)
and cached locally. We intentionally avoid `az account management-group` commands
because they can trigger Microsoft.Management/register/action (provider registration),
which is a write permission many Reader roles do not have.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

CACHE_VERSION = 3
DEFAULT_CACHE_PATH = Path.home() / ".cache" / "aks-subscription-mg-map.json"
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

AKS_ARG_QUERY = """
Resources
| where type =~ 'microsoft.containerservice/managedclusters'
| project
    aksName=name,
    subscriptionId=tolower(tostring(subscriptionId)),
    resourceGroup,
    status=coalesce(tostring(properties.powerState.code), 'Unknown')
| order by aksName asc
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
    """
    Resolve identity from the currently logged-in Azure CLI session.

    The active subscription from `az account show` is only the CLI default context.
    Tenant-wide queries (management groups, Resource Graph) use the login token and
    return all subscriptions/resources this user can access within that tenant.
    """
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


def get_tenant_id() -> str:
    return get_az_context().tenant_id


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
    """
    Build an ordered chain root → direct parent (Azure ARG order).

    `managementGroupAncestorsChain` is root-first. Some tenants omit the direct
    parent in the chain; append `properties.managementGroupId` when needed.
    """
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
    """
    Format MG path child → parent → … → root for display.

    Returns (hierarchyPath, directManagementGroupId, allManagementGroupIds).
    """
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
    """Subscriptions visible to the logged-in user within the active tenant."""
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
    # Same tenant, different user may have different RBAC visibility.
    cached_user = str(cache.get("builtBy") or "").strip()
    if cached_user and cached_user != ctx.user_name:
        return False
    return bool(cache.get("subscriptions"))


def load_cache(cache_path: Path) -> dict[str, Any] | None:
    if not cache_path.is_file():
        return None
    try:
        return json.loads(cache_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
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


def fetch_aks_clusters(*, quiet: bool) -> list[dict[str, str]]:
    log("Querying AKS clusters across tenant...", quiet=quiet)
    rows: list[dict[str, str]] = []
    for item in graph_query_all(AKS_ARG_QUERY):
        rows.append(
            {
                "aksName": str(item.get("aksName") or ""),
                "subscriptionId": str(item.get("subscriptionId") or "").lower(),
                "resourceGroup": str(item.get("resourceGroup") or ""),
                "status": str(item.get("status") or "Unknown"),
            }
        )
    return rows


def enrich_clusters(
    clusters: list[dict[str, str]],
    subscription_map: dict[str, dict[str, str]],
    mg_filter: str | None,
) -> list[dict[str, str]]:
    enriched: list[dict[str, str]] = []
    mg_filter_lower = (mg_filter or "").lower()

    for cluster in clusters:
        sub_id = cluster["subscriptionId"]
        sub_meta = subscription_map.get(sub_id, {})
        row = {
            "aksName": cluster["aksName"],
            "subscriptionName": sub_meta.get("subscriptionName", ""),
            "resourceGroup": cluster["resourceGroup"],
            "managementGroupName": sub_meta.get("managementGroup", ""),
            "status": cluster["status"],
        }

        if mg_filter_lower:
            mg_path = str(row["managementGroupName"]).lower()
            mg_ids = [str(x).lower() for x in sub_meta.get("managementGroupIds", [])]
            direct_mg = str(sub_meta.get("managementGroupId", "")).lower()
            if (
                mg_filter_lower not in mg_path
                and mg_filter_lower not in direct_mg
                and not any(mg_filter_lower in mg_id for mg_id in mg_ids)
            ):
                continue

        enriched.append(row)

    enriched.sort(key=lambda row: row["aksName"].lower())
    return enriched


def format_table(rows: list[dict[str, str]]) -> str:
    mg_width = max(
        [len("Management Group")] + [len(row["managementGroupName"]) for row in rows]
    )
    mg_width = min(max(mg_width, 30), 120)

    header = (
        f"{'AKS Name':<40} {'Subscription':<35} {'Resource Group':<30} "
        f"{'Management Group':<{mg_width}} {'Status':<10}"
    )
    divider = (
        f"{'--------':<40} {'------------':<35} {'--------------':<30} "
        f"{'-' * mg_width:<{mg_width}} {'------':<10}"
    )
    lines = [header, divider]
    for row in rows:
        mg_label = row["managementGroupName"]
        if len(mg_label) > mg_width:
            mg_label = mg_label[: mg_width - 3] + "..."
        lines.append(
            f"{row['aksName']:<40} {row['subscriptionName']:<35} {row['resourceGroup']:<30} "
            f"{mg_label:<{mg_width}} {row['status']:<10}"
        )
    return "\n".join(lines)


def format_output(rows: list[dict[str, str]], fmt: str) -> str:
    if fmt == "json":
        return json.dumps(rows, indent=2)
    if fmt == "tsv":
        lines = ["aksName\tsubscriptionName\tresourceGroup\tmanagementGroupName\tstatus"]
        for row in rows:
            lines.append(
                "\t".join(
                    [
                        row["aksName"],
                        row["subscriptionName"],
                        row["resourceGroup"],
                        row["managementGroupName"],
                        row["status"],
                    ]
                )
            )
        return "\n".join(lines)
    if fmt == "table":
        return format_table(rows)
    raise ValueError(f"Unsupported format: {fmt}")


def cmd_list_clusters(args: argparse.Namespace) -> int:
    ensure_az_login(quiet=args.quiet)
    ctx = get_az_context()
    log_az_context(ctx, quiet=args.quiet)
    subscription_map = get_subscription_map(
        ctx,
        cache_path=Path(args.cache_file),
        refresh=args.latest,
        quiet=args.quiet,
    )
    clusters = fetch_aks_clusters(quiet=args.quiet)
    rows = enrich_clusters(clusters, subscription_map, args.management_group)
    log(f"Found {len(rows)} AKS cluster(s).", quiet=args.quiet)

    output = format_output(rows, args.format)
    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output + "\n", encoding="utf-8")
        log(f"Saved to: {out_path}", quiet=args.quiet)
    else:
        print(output)
    return 0


def cmd_refresh_cache(args: argparse.Namespace) -> int:
    ensure_az_login(quiet=args.quiet)
    ctx = get_az_context()
    log_az_context(ctx, quiet=args.quiet)
    payload = build_cache(ctx, quiet=args.quiet)
    cache_path = Path(args.cache_file)
    save_cache(cache_path, payload)
    log(
        f"Cached {len(payload['subscriptions'])} subscription(s) at {cache_path}",
        quiet=args.quiet,
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="List AKS clusters tenant-wide with management group enrichment."
    )
    parser.add_argument(
        "--cache-file",
        default=str(DEFAULT_CACHE_PATH),
        help=f"Subscription map cache path (default: {DEFAULT_CACHE_PATH})",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser(
        "list-clusters",
        help="List AKS clusters (default command when invoked via aks.sh)",
    )
    list_parser.add_argument(
        "-f",
        "--format",
        choices=["table", "json", "tsv"],
        default="table",
        help="Output format (default: table)",
    )
    list_parser.add_argument(
        "-g",
        "--management-group",
        default="",
        help="Filter by management group id or display name (matches any level in the hierarchy)",
    )
    list_parser.add_argument("-o", "--output", default="", help="Write output to file")
    list_parser.add_argument(
        "-l",
        "--latest",
        action="store_true",
        help="Refresh subscription/management group cache before listing",
    )
    list_parser.add_argument("-q", "--quiet", action="store_true", help="Suppress progress logs")
    list_parser.set_defaults(func=cmd_list_clusters)

    refresh_parser = subparsers.add_parser(
        "refresh-cache",
        help="Rebuild and persist the subscription/management group cache",
    )
    refresh_parser.add_argument("-q", "--quiet", action="store_true")
    refresh_parser.set_defaults(func=cmd_refresh_cache)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except AzCliError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
