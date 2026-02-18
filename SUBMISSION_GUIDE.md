# AiFly Chrome Web Store Submission Guide

## Complete Checklist Before Submission

### ✅ Pre-Submission Setup

- [ ] You have a Google account
- [ ] You've paid the $5 Chrome Web Store developer registration fee
- [ ] Extension has been tested thoroughly on multiple websites
- [ ] All features work correctly:
  - [ ] Alt+Space hotkey opens messenger
  - [ ] ChatGPT and Gemini options work
  - [ ] Chat history saves correctly
  - [ ] Text selection popups work
  - [ ] Medication detection works
  - [ ] Font size controls work
  - [ ] Works on empty/blank tabs
- [ ] Icons are in place (icons/icon-16.png, icon-48.png, icon-128.png)
- [ ] API key storage works
- [ ] Escape key closes messenger
- [ ] No console errors or warnings

---

## Step-by-Step Submission Process

### Step 1: Prepare Your Files

1. **Package the extension**:

   ```bash
   cd "/Users/fadelhanoun/Chrome Extensions/Chrome AI"
   ./package.sh
   ```

2. **This creates a zip file** with all necessary files:
   - manifest.json
   - background.js
   - content.js
   - options.html
   - options.js
   - icons/ folder
   - Documentation files

### Step 2: Create Store Listing Assets

#### Screenshots (Required - 5 recommended)

You need screenshots showing your extension in action. Here's what to capture:

**Screenshot 1**: Main Messenger Interface

- Open AiFly on any website
- Show a conversation with:
  - Bold medication names
  - Bullet points
  - Clear, readable layout
- Suggested size: 1280x800 or 640x400 px

**Screenshot 2**: Hotkey Activation

- Show Alt+Space being pressed
- Show messenger appearing
- Caption: "Press Alt+Space anywhere to activate"

**Screenshot 3**: Provider Selection

- Show the ChatGPT/Gemini toggle in header
- Highlight the ease of switching

**Screenshot 4**: Smart Text Features

- Show text selection with popup
- Display Copy/Follow-up buttons

**Screenshot 5**: Settings/Options Page

- Show API key input fields
- Display the helpful links to get API keys

#### Icon (Required)

- Already available: `/icons/icon-128.png`
- Size: 128x128 pixels
- Format: PNG with transparency

#### Promotional Images (Optional but recommended)

- **Small tile**: 440x280 pixels (shown in Chrome Web Store search)
- **Large tile**: 920x680 pixels (shown on extension detail page)

To create these, expand your 128x128 icon with your branding colors.

### Step 3: Access Chrome Web Store Developer Dashboard

1. Go to: https://chrome.google.com/webstore/devcenter
2. Sign in with your Google account
3. Accept the terms and conditions
4. Pay the $5 registration fee (if not already done)

### Step 4: Create a New Item

1. Click **"Create new item"** button
2. You'll see a form with these sections:
   - **Upload your package** (the .zip file)
   - **Store listing**
   - **Availability**
   - **Payments**
   - **Review**

### Step 5: Upload Your Package

1. Click **"Choose file"** in the upload section
2. Select your `AiFly_YYYYMMDD_HHMMSS.zip` file from the package.sh output
3. Click **"Upload"**
4. Wait for validation (usually instant)
5. You'll see the extracted contents verified

### Step 6: Fill in Store Listing

#### In the Dashboard, Complete These Fields:

**Title** (50 character max)

```
AiFly - AI Assistant Messenger
```

**Summary / Teaser** (132 character max)

```
Instant AI assistant messenger. Access ChatGPT and Gemini with Alt+Space.
```

**Detailed Description** (4000 characters)
Use the text from `STORE_LISTING.md` - paste the "Main Description" and "Key Features" sections

**Language**

- Select: English

**Category**

- Select: **Productivity**

**Locale** (your target region)

- Keep as default or select specific countries
- Recommended: "All locales"

**More details** (if prompted):

- Developer name: [Your name]
- Developer contact: [Your email]
- Support page: [Link to your GitHub or support page]
- Privacy policy URL: Point to your PRIVACY_POLICY.md

### Step 7: Add Screenshots

1. Under "Additional assets" or "Screenshots":
2. Upload all 5 screenshots
3. Add descriptions:
   - Screenshot 1: "Main messenger interface with smart formatting"
   - Screenshot 2: "Quick activation with Alt+Space hotkey"
   - Screenshot 3: "Easy provider switching between ChatGPT and Gemini"
   - Screenshot 4: "Smart text selection with quick actions"
   - Screenshot 5: "Customizable settings and API key management"

### Step 8: Add Icon (if required)

1. If not auto-detected from package, upload your icon:
2. File: `/icons/icon-128.png`
3. Size must be exactly 128x128 pixels
4. Format: PNG with transparency

### Step 9: Privacy and Permissions

1. **Privacy Policy**:
   - Required: YES
   - Upload or link to: `PRIVACY_POLICY.md`
   - Or paste the content directly

2. **Permissions Justification**:
   - The system will ask why you need each permission
   - Copy from your manifest.json and explain:
     - storage: "To save chat history and API keys locally"
     - scripting: "To inject the messenger interface"
     - activeTab: "To know which tab is active"
     - <all_urls>: "To work on any website"

### Step 10: Visibility & Distribution

1. **Visibility**:
   - [ ] Public (recommended for initial launch)
   - Or: [x] Unlisted (only people with link can find it)

2. **Distribution**:
   - Ensure you retain ownership
   - No third-party co-hosting needed

### Step 11: Review & Submit

1. Read through all your information one final time
2. Check for typos, broken links, etc.
3. Verify screenshots are high quality
4. Click **"Submit for review"**

A confirmation message will appear stating your extension is in review.

---

## What Happens After Submission

### Review Timeline

- **Expected**: 24-72 hours
- **Maximum**: 7 days

### During Review, Google Will Check:

✅ **Code Quality**

- No malware or security issues
- No hard-coded credentials
- Proper permission usage

✅ **Functionality**

- Extension works as described
- Features function correctly
- Hotkey works
- Settings save properly

✅ **Privacy Compliance**

- No unauthorized data collection
- Privacy policy is legitimate
- Transparent about third-party API usage

✅ **Content Policies**

- No hateful content
- No deceptive practices
- Honest description

### Possible Outcomes:

#### ✅ Approved

Your extension is published! You'll receive:

- Confirmation email
- Store listing URL
- Instructions for updating in the future

#### ⚠️ Rejected

You'll receive specific reasons and can:

- Make requested changes
- Resubmit the fixed version
- Appeal if you disagree

#### ⏸️ Suspended

Rare, but possible if:

- Serious security issue found
- Violation of policies discovered
- Unresponsive to review requests

---

## After Approval: Promotion & Maintenance

### Share Your Extension

1. **Announce on Social Media**
   - Twitter/X: "Just published AiFly on Chrome Web Store! Instant AI assistance with Alt+Space... #ChromeExtension"
   - LinkedIn: Professional announcement to your network
   - Reddit: Share in r/chrome or r/webdev (follow subreddit rules)

2. **Get the Store Link**:
   - Format: `https://chrome.google.com/webstore/detail/{YOUR_EXTENSION_ID}`
   - Share in your README
   - Add to portfolio/GitHub

3. **Ask for Reviews**:
   - Request users to leave reviews
   - Reviews boost visibility
   - Respond to feedback professionally

### Maintain Your Extension

1. **Bug Fixes**: Test thoroughly before updating
2. **New Features**: Plan updates based on user feedback
3. **Version Bumps**: Update version in manifest.json
4. **Resubmit**: Use same process for updates
5. **Monitor Reviews**: Check for bugs reported by users

---

## Troubleshooting Common Issues

### Issue: "Manifest Invalid"

- **Solution**: Validate manifest.json against the schema
- Use: manifest.json validator online

### Issue: "Missing Required Icon"

- **Solution**: Ensure icons/ folder with all three sizes exists
- Sizes needed: 16x16, 48x48, 128x128

### Issue: "Permissions Not Justified"

- **Solution**: Clearly explain why each permission is needed
- Be specific: "We need storage to save your chat history locally"

### Issue: "API Key Detected in Code"

- **Solution**: Ensure NO API keys are in any source files
- Double-check: `grep -r "sk-" . --exclude-dir=.git`

### Issue: "Extension Does Nothing"

- **Solution**: Google tested it in isolation or on their test sites
- Make sure hotkey works on: https://example.com, https://google.com
- Test on blank tabs (about:blank)

### Issue: "Data Collection Privacy Concern"

- **Solution**: Clearly state no data is collected by AiFly
- Explain 3rd party APIs (OpenAI, Google) handle user data separately
- Link to their privacy policies

---

## Quick Reference: File Structure

After running `package.sh`, your zip contains:

```
AiFly_YYYYMMDD_HHMMSS.zip
├── manifest.json
├── background.js
├── content.js
├── options.html
├── options.js
├── README.md
├── PRIVACY_POLICY.md
├── STORE_LISTING.md
└── icons/
    ├── icon-16.png
    ├── icon-48.png
    └── icon-128.png
```

---

## Final Checklist Before Hitting Submit

- [ ] All files packaged correctly
- [ ] Screenshots are clear and representative
- [ ] Description is typo-free and compelling
- [ ] Privacy policy is linked/included
- [ ] Icons are correct sizes
- [ ] Permissions are explained
- [ ] Tested on at least 3 different websites
- [ ] Tested on blank tab
- [ ] No API keys in any source code
- [ ] All links in description work
- [ ] Screenshots match actual extension appearance

---

## Success! 🎉

Once approved, you have:

- ✅ A published Chrome extension
- ✅ Professional credibility
- ✅ Portfolio piece to showcase
- ✅ Real users improving their productivity

**Congratulations on publishing AiFly!**

---

## Support

If you encounter issues during submission:

1. Check Chrome Web Store Help: https://support.google.com/chrome/a/answer/2714278
2. Review Chrome Extension Policies: https://chrome.google.com/webstore/category/extensions
3. Contact Google via the dashboard

Good luck! 🚀
