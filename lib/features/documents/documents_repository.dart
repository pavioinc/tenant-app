import 'dart:convert';
import 'dart:typed_data';
import '../../core/api_client.dart';
import '../../core/date_utils.dart' show shortDate;

class TenantDocument {
  const TenantDocument({
    required this.documentId,
    required this.label,
    required this.contentType,
    required this.uploadedAt,
    required this.status,
    this.fileSizeBytes,
    this.reviewNote,
  });

  final String documentId;
  final String label;
  final String contentType;
  final String uploadedAt;
  // 'not_reviewed' | 'verified' | 'rejected' — set by the property manager (see
  // tenant-service's tenant_documents.status); real data already returned by GET
  // /tenant/me/documents, just never surfaced to the renter before this redesign.
  final String status;
  // Null for documents uploaded before migration 039 — there's no byte stream left to
  // measure for those, only the already-uploaded S3 key.
  final int? fileSizeBytes;
  final String? reviewNote;

  factory TenantDocument.fromJson(Map<String, dynamic> json) => TenantDocument(
    documentId: json['document_id'] as String,
    label: json['label'] as String,
    contentType: json['content_type'] as String,
    uploadedAt: shortDate(json['uploaded_at'] as String),
    status: json['status'] as String? ?? 'not_reviewed',
    fileSizeBytes: json['file_size_bytes'] as int?,
    reviewNote: json['review_note'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'document_id': documentId,
    'label': label,
    'content_type': contentType,
    'uploaded_at': uploadedAt,
    'status': status,
    'file_size_bytes': fileSizeBytes,
    'review_note': reviewNote,
  };
}

/// tenant-service's `/tenant/me/documents` — tenant-uploaded documents (ID proofs,
/// etc.). Upload is a base64 JSON body, matching tenant-service's existing agreement-
/// document convention; list/download never return file bytes, only metadata or a
/// short-lived presigned URL.
class DocumentsRepository {
  DocumentsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<TenantDocument>> list(String token) async {
    final body = await _api.get(
      '/api/tenants/v1/tenant/me/documents',
      token: token,
    );
    final documents = body['documents'] as List;
    return documents
        .map((d) => TenantDocument.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  Future<TenantDocument> upload(
    String token, {
    required String label,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/documents', {
      'label': label,
      'content_type': contentType,
      'document_base64': base64Encode(bytes),
    }, token: token);
    return TenantDocument.fromJson(body);
  }

  Future<String> downloadUrl(String token, String documentId) async {
    final body = await _api.get(
      '/api/tenants/v1/tenant/me/documents/$documentId/download',
      token: token,
    );
    return body['download_url'] as String;
  }

  Future<void> delete(String token, String documentId) async {
    await _api.delete(
      '/api/tenants/v1/tenant/me/documents/$documentId',
      token: token,
    );
  }
}
