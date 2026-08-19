import 'dart:convert';
import 'dart:typed_data';
import '../../core/api_client.dart';

class TenantDocument {
  const TenantDocument({required this.documentId, required this.label, required this.contentType, required this.uploadedAt});

  final String documentId;
  final String label;
  final String contentType;
  final String uploadedAt;

  factory TenantDocument.fromJson(Map<String, dynamic> json) => TenantDocument(
    documentId: json['document_id'] as String,
    label: json['label'] as String,
    contentType: json['content_type'] as String,
    uploadedAt: json['uploaded_at'] as String,
  );

  Map<String, dynamic> toJson() => {'document_id': documentId, 'label': label, 'content_type': contentType, 'uploaded_at': uploadedAt};
}

/// tenant-service's `/tenant/me/documents` — tenant-uploaded documents (ID proofs,
/// etc.). Upload is a base64 JSON body, matching tenant-service's existing agreement-
/// document convention; list/download never return file bytes, only metadata or a
/// short-lived presigned URL.
class DocumentsRepository {
  DocumentsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<TenantDocument>> list(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/documents', token: token);
    final documents = body['documents'] as List;
    return documents.map((d) => TenantDocument.fromJson(d as Map<String, dynamic>)).toList();
  }

  Future<TenantDocument> upload(String token, {required String label, required String contentType, required Uint8List bytes}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/documents', {
      'label': label,
      'content_type': contentType,
      'document_base64': base64Encode(bytes),
    }, token: token);
    return TenantDocument.fromJson(body);
  }

  Future<String> downloadUrl(String token, String documentId) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/documents/$documentId/download', token: token);
    return body['download_url'] as String;
  }

  Future<void> delete(String token, String documentId) async {
    await _api.delete('/api/tenants/v1/tenant/me/documents/$documentId', token: token);
  }
}
