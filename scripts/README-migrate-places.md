# One-time places migration

This script prepares the 120 curated entries in `Viewfinder/Data/photo_spots_seed.json` plus the single currently approved entry in `RecommendationServer/submitted-spots.json` for the top-level Firestore `places` collection. It preserves source document IDs and does not change the app's data source.

The approved submission is normalized into the same public fields as seed places. Its `source` remains `user-submitted`; author identity, review metadata, and `photoDataBase64` are excluded. The server creates the submission's `imageURL` dynamically from the incoming request host, so it is not a stable stored URL. Its image binary is intentionally not written to Firestore and still needs a separately approved Firebase Storage migration before Firestore becomes the only place source.

## Safety defaults

```sh
npm run migrate:places
```

This is a local validation dry-run by default. It never writes to Firestore. If `VIEWFINDER_FIREBASE_PROJECT_ID` is set and Google Application Default Credentials are available, it also performs read-only existence checks for the expected document IDs. Without those settings, remote conflicts cannot be checked and the script reports that explicitly.

The input is pinned to 120 seed records and one approved submitted place (121 total). Any change in those reviewed counts, unsupported field, duplicate ID, invalid coordinate/theme, or invalid Firestore value stops the migration before Firestore access.

## Credentials and project selection

Use Google Application Default Credentials (ADC), not a credential committed to the repository. For local development, ADC can be configured through `gcloud auth application-default login`. The dry-run identity only needs Firestore read access; use a least-privilege viewer role for the remote read-only check. A later, separately approved commit identity will also need permission to create Firestore documents.

Set the intended Firebase/Google Cloud project explicitly:

```sh
export VIEWFINDER_FIREBASE_PROJECT_ID="photo-shoot-9b5d0"
gcloud auth application-default login
npm run migrate:places
```

Alternatively, store a service-account file under `.secrets/` (ignored by Git) or outside this checkout, then set `GOOGLE_APPLICATION_CREDENTIALS` to its absolute path. Keep the key out of shell history and never commit it. `.gitignore` ignores `.secrets/`, `.env`, and `.env.*` while allowing the empty `.env.example` template.

The command above is a dry-run: it validates all 121 local candidates, reads the current `places` document count, checks only those 121 document IDs for collisions, and reports would-create/would-skip counts. It performs no writes. If credentials are unavailable, the remote check fails explicitly instead of reporting a successful remote dry-run.

## Actual migration — only after explicit approval

```sh
npm run migrate:places -- --commit
```

`--commit` is the only write-enabled mode and is not approved or run as part of this preparation. Existing `places/{id}` documents are reported and skipped. Each new record is created with Firestore's create-only precondition, so a concurrent/existing document is never overwritten. The script then rereads the candidate documents and compares their IDs and migrated fields.

Do not use `--commit` until the 121-candidate remote dry-run report has been reviewed and separately approved.
