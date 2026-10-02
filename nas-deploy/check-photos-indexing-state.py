"""Read-only: CheckIndexingState for every Photos zone on the account.

Prints zone kind (Primary / Shared / Other) and state only -- no zone ids,
no credentials.
"""

import json
import os
import sys

sys.path.insert(0, "/app")

import icloudpy  # noqa: E402
from icloudpy import utils as icloudpy_utils  # noqa: E402

from src import (
    DEFAULT_CONFIG_FILE_PATH,
    DEFAULT_COOKIE_DIRECTORY,
    ENV_CONFIG_FILE_PATH_KEY,
    config_parser,
    read_config,
)  # noqa: E402

config = read_config(
    config_path=os.environ.get(ENV_CONFIG_FILE_PATH_KEY, DEFAULT_CONFIG_FILE_PATH)
)
username = config_parser.get_username(config=config)
api = icloudpy.ICloudPyService(
    apple_id=username,
    password=icloudpy_utils.get_password_from_keyring(username),
    cookie_directory=DEFAULT_COOKIE_DIRECTORY,
)
if api.requires_2fa:
    print("session needs 2FA; stopping")
    sys.exit(1)

from urllib.parse import urlencode  # noqa: E402

root = api._get_webservice_url("ckdatabasews")  # noqa: SLF001
endpoint = f"{root}/database/1/com.apple.photos.cloud/production/private"
params = dict(api.params)
params.update({"remapEnums": True, "getCurrentSyncToken": True})
session = api.session


def query_state(zone_id):
    resp = session.post(
        f"{endpoint}/records/query?{urlencode(params)}",
        data=json.dumps({"query": {"recordType": "CheckIndexingState"}, "zoneID": zone_id}),
        headers={"Content-type": "text/plain"},
    ).json()
    recs = resp.get("records") or []
    if not recs:
        return {"raw_keys": sorted(resp.keys())}
    fields = recs[0].get("fields", {})
    return {k: (v.get("value") if isinstance(v, dict) else v) for k, v in fields.items()}


zones = session.post(f"{endpoint}/zones/list", data="{}", headers={"Content-type": "text/plain"}).json().get("zones", [])


def kind(name):
    if name == "PrimarySync":
        return "Primary"
    if name.startswith("SharedSync-"):
        return "Shared"
    return "Other(" + name.split("-")[0] + ")"


for z in zones:
    print(f"{kind(z['zoneID']['zoneName']):40}", query_state(z["zoneID"]))
