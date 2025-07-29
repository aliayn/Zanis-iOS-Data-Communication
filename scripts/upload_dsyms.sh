#!/bin/bash

# Firebase Crashlytics dSYM Upload Script
# This script uploads debug symbols to Firebase for proper crash symbolication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSYM_DIR="$PROJECT_DIR/build/ios/Release-iphoneos"
DART_SYMBOLS_DIR="$PROJECT_DIR/build/debug-symbols"
GOOGLE_SERVICES_PLIST="$PROJECT_DIR/ios/Runner/GoogleService-Info.plist"

echo -e "${BLUE}🔥 Firebase Crashlytics dSYM Upload Script${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}❌ Firebase CLI not found. Please install it:${NC}"
    echo "npm install -g firebase-tools"
    exit 1
fi

# Check if build directory exists
if [ ! -d "$DSYM_DIR" ]; then
    echo -e "${RED}❌ iOS build directory not found: $DSYM_DIR${NC}"
    echo -e "${YELLOW}💡 Run: flutter build ios --release --split-debug-info=build/debug-symbols${NC}"
    exit 1
fi

# Check if Google Services plist exists
if [ ! -f "$GOOGLE_SERVICES_PLIST" ]; then
    echo -e "${RED}❌ GoogleService-Info.plist not found: $GOOGLE_SERVICES_PLIST${NC}"
    echo -e "${YELLOW}💡 Download it from Firebase Console and place it in ios/Runner/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Find and upload dSYM files
echo -e "${BLUE}📤 Uploading dSYM files...${NC}"
dsym_count=0

for dsym in $(find "$DSYM_DIR" -name "*.dSYM" -type d); do
    dsym_name=$(basename "$dsym")
    echo -e "${YELLOW}📦 Uploading: $dsym_name${NC}"
    
    if firebase crashlytics:symbols:upload "$dsym" --app="$(grep -A1 'GOOGLE_APP_ID' "$GOOGLE_SERVICES_PLIST" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')"; then
        echo -e "${GREEN}✅ Successfully uploaded: $dsym_name${NC}"
        ((dsym_count++))
    else
        echo -e "${RED}❌ Failed to upload: $dsym_name${NC}"
    fi
    echo ""
done

# Upload Dart symbols
echo -e "${BLUE}📤 Uploading Dart debug symbols...${NC}"
if [ -d "$DART_SYMBOLS_DIR" ]; then
    for symbol_file in "$DART_SYMBOLS_DIR"/*.symbols; do
        if [ -f "$symbol_file" ]; then
            symbol_name=$(basename "$symbol_file")
            echo -e "${YELLOW}📦 Uploading: $symbol_name${NC}"
            
            if firebase crashlytics:symbols:upload "$symbol_file" --app="$(grep -A1 'GOOGLE_APP_ID' "$GOOGLE_SERVICES_PLIST" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')"; then
                echo -e "${GREEN}✅ Successfully uploaded: $symbol_name${NC}"
                ((dsym_count++))
            else
                echo -e "${RED}❌ Failed to upload: $symbol_name${NC}"
            fi
            echo ""
        fi
    done
else
    echo -e "${YELLOW}⚠️  No Dart debug symbols found in: $DART_SYMBOLS_DIR${NC}"
fi

echo -e "${BLUE}===========================================${NC}"
echo -e "${GREEN}🎉 Upload completed! Uploaded $dsym_count symbol files${NC}"
echo ""
echo -e "${BLUE}📋 What's next:${NC}"
echo -e "1. ${GREEN}Test your app and trigger some crashes${NC}"
echo -e "2. ${GREEN}Check Firebase Console for symbolicated crash reports${NC}"
echo -e "3. ${GREEN}Crashes should now show readable stack traces${NC}"
echo ""
echo -e "${YELLOW}💡 Tip: Add this script to your CI/CD pipeline for automatic uploads${NC}"
echo ""