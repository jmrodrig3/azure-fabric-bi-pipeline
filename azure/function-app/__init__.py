import azure.functions as func
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential
import json, logging, os, base64, traceback

# -----------------------------------------------------------------------------
# Configuration via environment variables (no hard-coded identifiers)
# -----------------------------------------------------------------------------
STORAGE_ACCOUNT_NAME = os.getenv("STORAGE_ACCOUNT_NAME", "changeme-storage")
ACCOUNT_URL = os.getenv("ACCOUNT_URL", f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net")
BLOB_CONTAINER_NAME = os.getenv("BLOB_CONTAINER_NAME", "data-staging")
REQUIRED_ROLE = os.getenv("REQUIRED_ROLE", "DataIngest.Write")

# Tables and folders are generic; adjust as needed in your environment
TABLE_FOLDER_MAP = {
    "transaction": "transaction/",
    "merchant_fee": "merchant_fee/",
    "entity": "entity/",
}

# Keep auth ANONYMOUS only if you are fronting this with platform authentication (e.g., Easy Auth).
# Otherwise consider func.AuthLevel.FUNCTION or ADMIN.
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

def _get_roles_from_easy_auth(req: func.HttpRequest) -> set:
    """
    Extract roles from the platform-provided principal header.
    Header value is Base64-encoded JSON with a 'claims' array.
    This function is intentionally permissive about the claim 'typ' to reduce coupling.
    """
    header = req.headers.get("X-MS-CLIENT-PRINCIPAL")
    if not header:
        return set()
    try:
        decoded = base64.b64decode(header).decode("utf-8")
        obj = json.loads(decoded)
        roles = {
            c.get("val")
            for c in obj.get("claims", [])
            if c.get("val") and str(c.get("typ")).lower().endswith("role")
        }
        return roles
    except Exception:
        # Do not log the decoded header; it may contain user info.
        logging.warning("Unable to parse client principal header.")
        return set()

@app.route(route="ingest", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def ingest(req: func.HttpRequest) -> func.HttpResponse:
    # Minimal log line; avoid echoing request bodies or secrets
    logging.info("Ingest endpoint invoked.")

    try:
        # ---- Authorization (platform-provided) ----
        roles = _get_roles_from_easy_auth(req)
        if REQUIRED_ROLE not in roles:
            # Generic message; do not disclose details about roles or configuration
            return func.HttpResponse("Forbidden.", status_code=403)

        # ---- Validate body (no echoing back untrusted input) ----
        try:
            data = req.get_json()
        except ValueError:
            return func.HttpResponse("Invalid JSON.", status_code=400)

        filename = str(data.get("filename", "")).strip()
        upload_type = str(data.get("upload_type", "")).strip().lower()
        table = str(data.get("table", "")).strip().lower()

        if not filename or upload_type not in {"initial", "daily"} or table not in TABLE_FOLDER_MAP:
            return func.HttpResponse("Bad request.", status_code=400)

        # ---- Compute destination path (generic folder structure) ----
        folder_root = "initial" if upload_type == "initial" else "daily"
        folder = f"{folder_root}/{TABLE_FOLDER_MAP[table]}"
        blob_path = f"{folder}{filename}"

        # ---- Write to Blob using Managed Identity (no secrets in code) ----
        credential = DefaultAzureCredential(exclude_shared_token_cache_credential=True)
        bsc = BlobServiceClient(account_url=ACCOUNT_URL, credential=credential)
        blob = bsc.get_blob_client(container=BLOB_CONTAINER_NAME, blob=blob_path)

        # Store the original payload as-is (or replace with the actual file bytes you receive)
        blob.upload_blob(json.dumps(data).encode("utf-8"), overwrite=True)

        # Do not reveal folder structure or exact path in the response
        return func.HttpResponse("Accepted.", status_code=200)

    except Exception:
        # Log a concise server-side error without returning internals to the client
        logging.error("Ingestion failed.", exc_info=True)
        return func.HttpResponse("Server error.", status_code=500)
