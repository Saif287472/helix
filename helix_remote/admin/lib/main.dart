import 'package:flutter/material.dart';
import 'package:helix_admin/src/app.dart';
import 'package:helix_admin/src/services/admin_services.dart';

void main() {
  runApp(HelixAdminApp(services: AdminServices.production()));
}
