# Firebase Service Account Setup Guide

## 📋 Overview

To enable background notifications, you need to configure the **Firebase Service Account** in Supabase. This allows the Edge Functions to authenticate with Firebase Cloud Messaging V1 API.

## 🔑 Step-by-Step Instructions

### Step 1: Access Google Cloud Console

1. Open your browser and go to: https://console.cloud.google.com/iam-admin/serviceaccounts
2. **Sign in** with your Google account
3. Make sure the **SOSit** project is selected (check top dropdown)

### Step 2: Find Your Service Account

You should see a service account that looks like:
- **Name**: `firebase-adminsdk-xxxxx@sosit-64bfe.iam.gserviceaccount.com`
- **Description**: Firebase Admin SDK Service Agent

If you don't see one, you might see:
- `Firebase Admin SDK Service Agent`
- Or a service account starting with `firebase-adminsdk`

### Step 3: Generate a New Key

1. Click on the **service account email** (the one with firebase-adminsdk)
2. Go to the **Keys** tab at the top
3. Click **Add Key** dropdown
4. Select **Create new key**
5. Choose **JSON** as the key type
6. Click **Create**

A JSON file will be downloaded to your computer (usually to Downloads folder).

**Example filename:** `sosit-64bfe-firebase-adminsdk-xxxxx.json`

### Step 4: Prepare the JSON Content

Open the downloaded JSON file in a text editor (Notepad, VS Code, etc.).

The file should look like this:

```json
{
  "type": "service_account",
  "project_id": "sosit-64bfe",
  "private_key_id": "abc123...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-xxxxx@sosit-64bfe.iam.gserviceaccount.com",
  "client_id": "123456789...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  ...
}
```

**Keep this file secure! It contains sensitive credentials.**

### Step 5: Set in Supabase (PowerShell Method)

Open **PowerShell** and run:

```powershell
# Install Supabase CLI (if not already installed)
npm install -g supabase

# Login to Supabase
supabase login

# Link to your SOSit project
supabase link --project-ref ctsnpupbpcznwbbtqdln

# Set the service account (replace with actual path to your downloaded JSON)
$json = Get-Content "C:\Users\USER\Downloads\sosit-64bfe-firebase-adminsdk-xxxxx.json" -Raw
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$json"

# Also set the Firebase Project ID
supabase secrets set FIREBASE_PROJECT_ID=sosit-64bfe
```

### Step 6: Verify Secrets are Set

```powershell
# List all secrets
supabase secrets list
```

You should see:
- ✅ `FIREBASE_SERVICE_ACCOUNT`
- ✅ `FIREBASE_PROJECT_ID`
- ✅ `SUPABASE_URL` (should already exist)
- ✅ `SUPABASE_SERVICE_ROLE_KEY` (should already exist)

### Step 7: Deploy Edge Functions

```powershell
# Navigate to your project folder
cd "C:\Users\USER\Desktop\SOSit"

# Deploy both notification functions
supabase functions deploy send-parent-alerts
supabase functions deploy send-station-alerts
```

Wait for the deployment to complete. You should see:
```
✓ Deployed Function send-parent-alerts
✓ Deployed Function send-station-alerts
```

## ✅ Verification

### Test Edge Function Logs

```powershell
# Monitor parent alerts (in real-time)
supabase functions logs send-parent-alerts --tail
```

Trigger a test alert and look for:
- 🔑 "Getting Firebase access token..."
- ✅ "Access token obtained"
- ✅ "FCM V1 notification sent successfully"

## 🔒 Security Best Practices

### Protect Your Service Account Key

- ✅ **DO**: Store the JSON file securely (encrypted folder, password manager)
- ✅ **DO**: Set restricted permissions on the file
- ✅ **DO**: Delete old/unused keys from Google Cloud Console
- ❌ **DON'T**: Commit the JSON file to Git
- ❌ **DON'T**: Share the JSON content publicly
- ❌ **DON'T**: Email or message the key

### Add to .gitignore

Make sure your `.gitignore` includes:

```
# Firebase service account keys
*firebase-adminsdk*.json
service-account*.json
```

### Rotate Keys Regularly

Every 3-6 months:
1. Create a new key in Google Cloud Console
2. Update Supabase secret with new key
3. Redeploy Edge Functions
4. Delete old key from Google Cloud Console

## 🐛 Troubleshooting

### "FIREBASE_SERVICE_ACCOUNT not configured" error

**Problem**: The secret wasn't set properly.

**Solution**:
```powershell
# Try setting it again with proper escaping
$json = Get-Content "path\to\your\file.json" -Raw
$json = $json -replace '"', '\"'
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$json"
```

### "Failed to get access token" error

**Problem**: The JSON might be malformed or the service account lacks permissions.

**Solutions**:
1. **Verify JSON is valid**: Open in a JSON validator
2. **Check service account permissions** in Google Cloud:
   - Go to IAM & Admin → IAM
   - Find your service account
   - Should have "Firebase Admin SDK Administrator Service Agent" role
3. **Try creating a new key**

### "Cannot find module" errors in Edge Functions

**Problem**: TypeScript errors in Deno Edge Functions (these are normal!)

**Solution**: Ignore these errors. They only appear in VS Code but don't affect deployment.

### Deployment fails with authentication error

**Problem**: Not logged in or not linked to project.

**Solution**:
```powershell
# Re-login
supabase logout
supabase login

# Re-link to project
supabase link --project-ref ctsnpupbpcznwbbtqdln

# Try deploying again
supabase functions deploy send-parent-alerts
```

## 📝 Alternative: Using Supabase Dashboard

If PowerShell method doesn't work:

1. Go to [Supabase Dashboard](https://app.supabase.com/)
2. Select your **SOSit** project
3. Go to **Project Settings** → **Edge Functions** → **Secrets**
4. Click **Add new secret**
5. Name: `FIREBASE_SERVICE_ACCOUNT`
6. Value: Paste the entire JSON content
7. Click **Save**
8. Repeat for `FIREBASE_PROJECT_ID` with value `sosit-64bfe`

## 🎯 Success Indicators

You'll know it's working when:

✅ Secrets are visible in `supabase secrets list`  
✅ Edge Functions deploy without errors  
✅ Function logs show "Access token obtained"  
✅ Function logs show "FCM V1 notification sent successfully"  
✅ Devices receive notifications in background  

## 📞 Need Help?

If you're still having issues:

1. **Check function logs**: `supabase functions logs send-parent-alerts`
2. **Verify service account permissions** in Google Cloud Console
3. **Ensure Firebase Cloud Messaging API is enabled** in Google Cloud
4. **Try creating a fresh service account key**

---

**Last Updated**: November 11, 2025  
**API Version**: Firebase Cloud Messaging V1  
**Status**: Production Ready ✅
