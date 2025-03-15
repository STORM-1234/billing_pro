// lib/models/company.dart


class Company {
  String docId;
  String name;
  String phone;
  String? address;
  String? description;
  String? crNumber;
  String? vatNumber;
  double outstanding;
  bool isSynced; // true if changes are in Firestore, false if offline or error

  Company({
    required this.docId,
    required this.name,
    required this.phone,
    this.address,
    this.description,
    this.outstanding = 0.0,
    this.isSynced = true,
    this.crNumber,
    this.vatNumber,
  });
}
