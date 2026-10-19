# Reviewed museum image transport

Artwork metadata and rights approval remain independent of transport approval. Each adopted work must retain its museum object URL, image-specific public-domain/CC0 evidence, checked date and attribution. Museum descriptions are citation-only; the app writes its own summaries. Existing attribution and rights disclosures remain visible in main app and Share Extension.

The API schema, Core image-URL projection and native downloader agree on these exact HTTPS hosts: `api.nga.gov`, `images.metmuseum.org`, and `openaccess-cdn.clevelandart.org`. Subdomains, suffix matches, private/IP addresses, credentials, fragments, nonstandard ports and arbitrary query parameters are rejected. There is no user-supplied image URL input.

Cleveland's official object pages may supply `www.clevelandart.org/_next/image`. That one path is accepted only with exactly `url`, `w=1920`, `q=75`; its decoded source must be HTTPS `piction.clevelandart.org/cma/ump.di` with exactly the known image identifier fields `e`, `s`, `se`, `v`, `f`. A general remote URL, redirect field, duplicate parameter or different source host/path is rejected. Decode HTML entity escaping from source pages before catalog registration; do not silently alter arbitrary URLs at download time.

The downloader retains an ephemeral cookie-free session, rejects every redirect, checks HTTP status, final URL and image MIME type, enforces an 8 MB streamed limit and validates image content. The UI creates a bounded 1600px thumbnail. No account credentials are attached. Public artwork cache remains separate from private conversation state.

Primary specifications checked 2026-10-18:

- Met API: https://metmuseum.github.io/ — `isPublicDomain` and `primaryImage`/`primaryImageSmall` fields; https://www.metmuseum.org/hubs/open-access
- Cleveland API: https://openaccess-api.clevelandart.org/ — `share_license_status=CC0`; https://www.clevelandart.org/open-access
- NGA official Data Dictionary: https://raw.githubusercontent.com/NationalGalleryOfArt/opendata/main/documentation/Data%20Dictionary.txt — published image `openaccess=1`, distinct from metadata licensing.

Transport acceptance does not mean any host's every image is public domain. The reviewed catalog must establish rights separately for every image, and actual HTTP fetch/decode and native rendering remain adoption gates.
