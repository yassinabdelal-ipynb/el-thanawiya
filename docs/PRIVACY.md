# Privacy

The Android app stores the user's profile, courses, assessments, and theme in private local preferences using `shared_preferences`. It does not require an account or call a remote inference service. The release main manifest has no Internet permission. Android backup and transfer of app records are disabled; uninstalling removes local records.

Private app storage is not a promise of application-level encryption. Device access, a compromised operating system, screenshots, and information the user deliberately exports remain outside this design.

The browser demo is a separate preview with illustrative inputs. Its sample course names and grades are not evidence of accuracy on those subjects. Do not enter sensitive student data into a shared demo.

The Python CLI and local API process the JSON payload supplied to them. The server binds to localhost and is intended for local development. It has no production authentication or managed student database.

The repository's research outputs come from the attributed UCI and OULAD public sources. They do not contain records collected by the Android app. Do not submit real student names, contact details, private grades, credentials, or signing keys in GitHub issues or pull requests.
