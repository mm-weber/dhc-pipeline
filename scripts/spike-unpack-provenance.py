#!/usr/bin/env python3
"""spike-unpack-provenance.py <bundle file> <repository> <subject digest>

Spike only (task 18.3's confirming run on the never-merging branch); the real
script is written by TDD once the owner has chosen the path.

Writes GitHub's provenance attestation for <subject digest> as one more layer
of the attestation manifest cosign v2 reads (`<repository>:sha256-<hex>.att`),
so the verifiers this repository pins keep one layout to read.

<bundle file> is either what `actions/attest-build-provenance` leaves at its
`bundle-path` output (one Sigstore bundle per line) or the answer of GitHub's
attestation store (`GET /repos/<owner>/<repo>/attestations/<digest>`).

Nothing is signed here and nothing is re-serialised that a signature covers:
  layer        the DSSE envelope, byte for byte as the transparency log hashed it
  annotations  the predicate type, the signing certificate (PEM), the log entry
               with its signed entry timestamp
A bundle whose log entry carries no signed entry timestamp (the second Rekor
log issues none) cannot be carried by this layout and is refused by name.

Registry credentials come from REGISTRY_USER / REGISTRY_PASSWORD and are only
ever sent to the registry's own token endpoint; nothing here prints them.
"""
import base64
import hashlib
import json
import os
import sys
import textwrap
import urllib.error
import urllib.parse
import urllib.request

PROVENANCE = "https://slsa.dev/provenance/v1"
MANIFEST = "application/vnd.oci.image.manifest.v1+json"
ENVELOPE = "application/vnd.dsse.envelope.v1+json"


def die(msg):
    print(f"::error::spike-unpack-provenance: {msg}", file=sys.stderr)
    sys.exit(1)


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def bundles(path):
    text = open(path, encoding="utf-8").read().strip()
    try:
        doc = json.loads(text)
    except json.JSONDecodeError:
        return [json.loads(line) for line in text.splitlines() if line.strip()]
    if isinstance(doc, dict) and "attestations" in doc:
        return [a["bundle"] for a in doc["attestations"]]
    return [doc]


def pick(path, subject):
    """The provenance bundle whose statement names <subject>."""
    hexd = subject.split(":", 1)[1]
    for b in bundles(path):
        env = b.get("dsseEnvelope") or {}
        try:
            st = json.loads(base64.b64decode(env["payload"]))
        except (KeyError, ValueError):
            continue
        if st.get("predicateType") != PROVENANCE:
            continue
        if any(s.get("digest", {}).get("sha256") == hexd for s in st.get("subject", [])):
            return b
    die(f"no {PROVENANCE} bundle in {path} names {subject}")


def layer(bundle):
    env = bundle["dsseEnvelope"]
    if len(env.get("signatures", [])) != 1:
        die("the envelope carries more or fewer than one signature")
    raw = json.dumps(
        {"payload": env["payload"], "payloadType": env["payloadType"],
         "signatures": [{"sig": env["signatures"][0]["sig"]}]},
        separators=(",", ":")).encode()
    vm = bundle["verificationMaterial"]
    entries = vm.get("tlogEntries", [])
    if len(entries) != 1:
        die(f"the bundle carries {len(entries)} transparency log entries, expected one")
    t = entries[0]
    set_ = (t.get("inclusionPromise") or {}).get("signedEntryTimestamp")
    if not set_:
        die("the log entry carries no signed entry timestamp (inclusion promise); "
            "the old attestation layout cannot carry such an entry, refusing")
    body = json.loads(base64.b64decode(t["canonicalizedBody"]))
    if body.get("kind") != "dsse":
        die(f"the log entry is of kind {body.get('kind')!r}, expected 'dsse'")
    want = body["spec"]["envelopeHash"]["value"]
    if hashlib.sha256(raw).hexdigest() != want:
        die("the envelope does not hash to the value the transparency log recorded")
    der = base64.b64decode(vm["certificate"]["rawBytes"])
    pem = ("-----BEGIN CERTIFICATE-----\n"
           + "\n".join(textwrap.wrap(base64.b64encode(der).decode(), 64))
           + "\n-----END CERTIFICATE-----\n")
    rekor = {"SignedEntryTimestamp": set_,
             "Payload": {"body": t["canonicalizedBody"], "integratedTime": int(t["integratedTime"]),
                         "logIndex": int(t["logIndex"]),
                         "logID": base64.b64decode(t["logId"]["keyId"]).hex()}}
    desc = {"mediaType": ENVELOPE, "size": len(raw), "digest": digest(raw), "annotations": {
        "dev.cosignproject.cosign/signature": "",
        "predicateType": PROVENANCE,
        "dev.sigstore.cosign/certificate": pem,
        "dev.sigstore.cosign/bundle": json.dumps(rekor, separators=(",", ":"))}}
    return raw, desc, int(t["logIndex"])


class Registry:
    def __init__(self, repository):
        host, _, self.name = repository.partition("/")
        scheme = "http" if os.environ.get("REGISTRY_PLAIN_HTTP") else "https"
        self.root = f"{scheme}://{host}"
        self.base = f"{self.root}/v2/{self.name}"
        self.token = None
        self.opener = urllib.request.build_opener(_Redirect)
        self._login()

    def _login(self):
        try:
            self.opener.open(urllib.request.Request(f"{self.root}/v2/"))
            return
        except urllib.error.HTTPError as e:
            if e.code != 401:
                die(f"the registry answered {e.code} to /v2/")
            challenge = e.headers.get("WWW-Authenticate", "")
        fields = dict(urllib.request.parse_keqv_list(
            urllib.request.parse_http_list(challenge.partition(" ")[2])))
        query = urllib.parse.urlencode({"service": fields.get("service", ""),
                                        "scope": f"repository:{self.name}:pull,push"})
        req = urllib.request.Request(f"{fields['realm']}?{query}")
        user, password = os.environ.get("REGISTRY_USER", ""), os.environ.get("REGISTRY_PASSWORD", "")
        if password:
            req.add_header("Authorization",
                           "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
        try:
            self.token = json.load(self.opener.open(req))["token"]
        except urllib.error.HTTPError as e:
            die(f"the registry's token endpoint answered {e.code}")

    def call(self, method, url, data=None, ctype=None, accept=None, missing_ok=False):
        if url.startswith("/"):
            url = self.root + url
        req = urllib.request.Request(url, data=data, method=method)
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        if ctype:
            req.add_header("Content-Type", ctype)
        if accept:
            req.add_header("Accept", accept)
        try:
            return self.opener.open(req)
        except urllib.error.HTTPError as e:
            if missing_ok and e.code == 404:
                return None
            die(f"{method} {url.split('?')[0]} answered {e.code}: {e.read(300).decode(errors='replace')}")

    def push_blob(self, data):
        r = self.call("POST", f"{self.base}/blobs/uploads/", b"")
        loc = r.headers["Location"]
        loc += ("&" if "?" in loc else "?") + "digest=" + urllib.parse.quote(digest(data), safe="")
        self.call("PUT", loc, data, "application/octet-stream")


class _Redirect(urllib.request.HTTPRedirectHandler):
    """A registry hands blob reads on to a storage host; the token stays home."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urllib.parse.urlsplit(newurl).netloc != urllib.parse.urlsplit(req.full_url).netloc:
            new.headers.pop("Authorization", None)
        return new


def main():
    if len(sys.argv) != 4 or not sys.argv[3].startswith("sha256:"):
        die("usage: spike-unpack-provenance.py <bundle file> <repository> <subject digest>")
    path, repository, subject = sys.argv[1:4]
    raw, desc, log_index = layer(pick(path, subject))
    reg = Registry(repository)
    tag = "sha256-" + subject.split(":", 1)[1] + ".att"
    r = reg.call("GET", f"{reg.base}/manifests/{tag}", accept=MANIFEST, missing_ok=True)
    if r is None:
        man = {"schemaVersion": 2, "mediaType": MANIFEST,
               "config": {"mediaType": "application/vnd.oci.image.config.v1+json"}, "layers": []}
        cfg = {"architecture": "", "created": "0001-01-01T00:00:00Z", "history": [], "os": "",
               "rootfs": {"type": "layers", "diff_ids": []}, "config": {}}
    else:
        man = json.load(r)
        cfg = json.load(reg.call("GET", f"{reg.base}/blobs/{man['config']['digest']}"))
    before = len(man["layers"])
    # One provenance layer per digest: a second run replaces the first.
    man["layers"] = [l for l in man["layers"]
                     if l.get("annotations", {}).get("predicateType") != PROVENANCE]
    replaced = before - len(man["layers"])
    man["layers"].append(desc)
    cfg["rootfs"]["diff_ids"] = [l["digest"] for l in man["layers"]]
    cfg["history"] = [{"created": "0001-01-01T00:00:00Z"} for _ in man["layers"]]
    config = json.dumps(cfg, separators=(",", ":")).encode()
    man["config"].update({"size": len(config), "digest": digest(config)})
    reg.push_blob(raw)
    reg.push_blob(config)
    reg.call("PUT", f"{reg.base}/manifests/{tag}", json.dumps(man, separators=(",", ":")).encode(), MANIFEST)
    print(f"unpacked the provenance for {subject} into {tag}")
    print(f"envelope {desc['digest']} hashes to the logged value, log index {log_index}")
    print(f"layers before {before}, provenance layers replaced {replaced}, layers now {len(man['layers'])}:")
    for l in man["layers"]:
        print(f"  {l.get('annotations', {}).get('predicateType')}")


if __name__ == "__main__":
    main()
