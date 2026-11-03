# Happy Live Admin

This directory is reserved for the separate administration web client.

## Contract
- Connect only to the Laravel API under `/api/v1`.
- Require server-verified administrator authentication and granular permissions.
- Record sensitive actions in an immutable audit trail.
- Never connect directly to MySQL or trust role flags supplied by a browser.

The admin interface will be implemented after the authentication and authorization API contracts are established. This avoids shipping a decorative dashboard with no secure backend.
