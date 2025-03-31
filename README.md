# SRE_Automation_GCP

Step 1: Enable APIs
Go to your GCP project and enable:

Admin SDK API
Cloud Identity API


🔐 Step 2: Set Up Authentication
There are two ways, depending on your use case:

🔹 Option A: OAuth2 User Auth (Interactive Apps)
Use this if you’re building an internal tool and can get user consent.

You'll need OAuth client credentials.

Scopes needed:

plaintext
Copy
Edit
https://www.googleapis.com/auth/admin.directory.user
https://www.googleapis.com/auth/admin.directory.group
https://www.googleapis.com/auth/cloud-identity.groups.readonly
🔹 Option B: Service Account with Domain-Wide Delegation
This is the preferred method for automation and GCP backend services.

Create a service account.

Enable "Domain-wide delegation".

Grant it access in your Admin Console:
Admin Console > Security > API Controls > Domain-wide Delegation > Add New

💻 Step 3: Code Sample (Python)
Here’s an example using google-api-python-client and domain-wide delegation to access users in the domain:

python
Copy
Edit
from google.oauth2 import service_account
from googleapiclient.discovery import build

# Path to your service account JSON
SERVICE_ACCOUNT_FILE = 'your-service-account.json'
SCOPES = ['https://www.googleapis.com/auth/admin.directory.user.readonly']

# The email of an admin user in your domain
DELEGATED_ADMIN = 'admin@yourdomain.com'

# Auth with domain-wide delegation
credentials = service_account.Credentials.from_service_account_file(
    SERVICE_ACCOUNT_FILE,
    scopes=SCOPES
).with_subject(DELEGATED_ADMIN)

# Build Admin SDK directory service
service = build('admin', 'directory_v1', credentials=credentials)

# List first 10 users
results = service.users().list(customer='my_customer', maxResults=10, orderBy='email').execute()
users = results.get('users', [])

for user in users:
    print(f"{user['primaryEmail']} ({user['name']['fullName']})")
📚 Some Common Admin REST Endpoints
Purpose	API	Endpoint
List Users	Admin SDK	GET /admin/directory/v1/users
Get User	Admin SDK	GET /admin/directory/v1/users/{userKey}
List Groups	Cloud Identity	GET /v1/groups
List Group Members	Admin SDK	GET /admin/directory/v1/groups/{groupKey}/members
Suspend User	Admin SDK	PATCH /admin/directory/v1/users/{userKey} with {suspended: true}
📦 Bonus: Use gcloud CLI for quick test
bash
Copy
Edit
gcloud auth login --impersonate-service-account=admin@yourdomain.com
gcloud identity groups list
