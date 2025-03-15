const { onObjectFinalized } = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");
admin.initializeApp();

const xlsx = require("xlsx");
const path = require("path");
const os = require("os");
const fs = require("fs");

/**
 * Triggered when a file is finalized (uploaded) in Cloud Storage.
 * We only care about files in "price_uploads/".
 * We'll parse the Excel file and write items to Firestore without duplicates.
 */
exports.processExcelFile = onObjectFinalized(async (event) => {
  try {
    const metadata = event.data;
    if (!metadata) {
      console.log("No object metadata found.");
      return;
    }

    // The name of the file in the bucket
    const filePath = metadata.name || "";
    if (!filePath.startsWith("price_uploads/")) {
      console.log("File not in price_uploads folder, skipping...");
      return;
    }

    const bucketName = metadata.bucket;
    console.log(`File path: ${filePath}, bucket: ${bucketName}`);

    // Download the file locally
    const bucket = admin.storage().bucket(bucketName);
    const tempFilePath = path.join(os.tmpdir(), path.basename(filePath));
    await bucket.file(filePath).download({ destination: tempFilePath });
    console.log(`Excel file downloaded locally to ${tempFilePath}`);

    // Parse the Excel
    const workbook = xlsx.readFile(tempFilePath);
    const sheetName = workbook.SheetNames[0];
    const worksheet = workbook.Sheets[sheetName];
    const jsonData = xlsx.utils.sheet_to_json(worksheet, { header: 1 });

    // Convert rows to an array of { itemName, price }
    const items = [];
    for (let i = 1; i < jsonData.length; i++) {
      const row = jsonData[i];
      if (!row || row.length < 3) continue;
      const itemName = row[1] ? String(row[1]).trim() : "Unknown";
      const price = parseFloat(row[2]) || 0.0;

      if (itemName && itemName !== "Unknown") {
        items.push({ itemName, price });
      }
    }

    console.log(`Found ${items.length} items to insert/update in Firestore.`);

    // 1) Build a map of existing itemName -> docRef from Firestore
    const pricesCol = admin.firestore().collection("prices");
    const snapshot = await pricesCol.get();
    const existingMap = {}; // { itemName: docRef }

    snapshot.forEach((doc) => {
      const data = doc.data();
      const existingName = data.itemName;
      if (existingName) {
        existingMap[existingName] = doc.ref;
      }
    });

    // 2) Write new/updated items in batches
    await batchWriteItems(items, existingMap);

    // Cleanup
    fs.unlinkSync(tempFilePath);
    console.log("Processed Excel file and removed temp file.");
  } catch (err) {
    console.error("Error processing Excel file:", err);
  }
});

/**
 * Writes items to Firestore in chunked batch commits.
 * - If itemName is found in existingMap, we update that doc.
 * - Otherwise, we create a new doc with doc() random ID.
 */
async function batchWriteItems(items, existingMap) {
  const db = admin.firestore();
  const chunkSize = 100; // Firestore limit is 500 ops, 100 is safer

  for (let start = 0; start < items.length; start += chunkSize) {
    const end = Math.min(start + chunkSize, items.length);
    const chunk = items.slice(start, end);

    const batch = db.batch();

    chunk.forEach((item) => {
      const { itemName, price } = item;

      // Check if there's already a doc with this itemName
      let docRef = existingMap[itemName];

      if (!docRef) {
        // No existing doc => create a new doc with random ID
        docRef = db.collection("prices").doc();
        // Also store it in the map so if another row has the same itemName,
        // we update the same doc
        existingMap[itemName] = docRef;
      }

      // Set with merge => create if doesn't exist, update if it does
      batch.set(docRef, {
        itemName: itemName,
        price: price,
      }, { merge: true });
    });

    await batch.commit();
    // optional delay to avoid spamming Firestore
    await new Promise((resolve) => setTimeout(resolve, 200));
  }

  console.log("All batches committed successfully (no duplicates).");
}
