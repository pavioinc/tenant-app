import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../theme/nivasa_colors.dart';

const complaintCategories = ['Electrical', 'Plumbing', 'Cleaning', 'Internet', 'Furniture', 'Noise', 'Other'];

const complaintStatusLabels = {'open': 'Open', 'in_progress': 'In progress', 'resolved': 'Resolved'};

/// Shared between ComplaintsScreen's list rows and ComplaintDetailScreen's header, so
/// the two can't drift on what each status looks like.
(Color, Color) complaintStatusColors(String status) => switch (status) {
  'resolved' => (NivasaColors.positiveTint, NivasaColors.positiveTextOnTint),
  'in_progress' => (NivasaColors.infoTint, NivasaColors.infoTextOnTint),
  _ => (NivasaColors.warningTint, NivasaColors.warningTextOnTint),
};

class Complaint {
  const Complaint({required this.complaintId, required this.category, required this.description, required this.status, required this.createdAt});

  final String complaintId;
  final String category;
  final String description;
  final String status;
  final String createdAt;

  factory Complaint.fromJson(Map<String, dynamic> json) => Complaint(complaintId: json['complaint_id'] as String, category: json['category'] as String, description: json['description'] as String, status: json['status'] as String, createdAt: shortDate(json['created_at'] as String));

  Map<String, dynamic> toJson() => {'complaint_id': complaintId, 'category': category, 'description': description, 'status': status, 'created_at': createdAt};
}

/// One entry in a complaint's detail thread — tenant-service's `complaint_notes` table
/// (2026-08-31), either manager- or tenant-authored. See tenant-service's
/// GET/POST /tenant/me/complaints/:id/notes.
class ComplaintNote {
  const ComplaintNote({required this.noteId, required this.authorType, required this.authorName, required this.body, required this.createdAt});

  final String noteId;
  final String authorType; // 'manager' | 'tenant'
  final String? authorName;
  final String body;
  final String createdAt;

  bool get isFromManager => authorType == 'manager';

  factory ComplaintNote.fromJson(Map<String, dynamic> json) => ComplaintNote(noteId: json['note_id'] as String, authorType: json['author_type'] as String, authorName: json['author_name'] as String?, body: json['body'] as String, createdAt: shortDate(json['created_at'] as String));

  Map<String, dynamic> toJson() => {'note_id': noteId, 'author_type': authorType, 'author_name': authorName, 'body': body, 'created_at': createdAt};
}

/// tenant-service's `/tenant/me/complaints` — ownership-scoped, same pattern as
/// Profile/Rentals/Renewal.
class ComplaintsRepository {
  ComplaintsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<Complaint>> list(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/complaints', token: token);
    final complaints = body['complaints'] as List;
    return complaints.map((c) => Complaint.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<Complaint> submit(String token, {required String category, required String description}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/complaints', {'category': category, 'description': description}, token: token);
    return Complaint.fromJson(body);
  }

  Future<List<ComplaintNote>> listNotes(String token, String complaintId) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/complaints/$complaintId/notes', token: token);
    final notes = body['notes'] as List;
    return notes.map((n) => ComplaintNote.fromJson(n as Map<String, dynamic>)).toList();
  }

  Future<ComplaintNote> addNote(String token, String complaintId, String body) async {
    final result = await _api.post('/api/tenants/v1/tenant/me/complaints/$complaintId/notes', {'body': body}, token: token);
    return ComplaintNote.fromJson(result);
  }
}
