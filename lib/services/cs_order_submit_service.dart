import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vanessa3/data/offline_pending_orders.dart';
import 'package:vanessa3/services/offline_write_service.dart';

/// Hasil submit order CS (online atau antrian offline).
class CsOrderSubmitResult {
  const CsOrderSubmitResult({
    required this.success,
    required this.offlineQueued,
    this.serverData,
    this.fakturData,
    this.offlineRef,
    this.queueItemId,
    this.errorMessage,
  });

  final bool success;
  final bool offlineQueued;
  final Map<String, dynamic>? serverData;
  final Map<String, dynamic>? fakturData;
  final String? offlineRef;
  final String? queueItemId;
  final String? errorMessage;
}

class CsOrderSubmitService {
  CsOrderSubmitService._();

  static Map<String, dynamic> mergeFakturData({
    required Map<String, dynamic> orderData,
    required Map<String, dynamic> serverOrOverlay,
    Map<String, dynamic>? extra,
  }) {
    final out = <String, dynamic>{
      ...orderData,
      ...serverOrOverlay,
      ...?extra,
    };
    return out;
  }

  static Map<String, dynamic> offlineFakturOverlay({
    required Map<String, dynamic> orderData,
    required String offlineRef,
  }) {
    return {
      ...orderData,
      'order_id': null,
      'offline_pending': true,
      'offline_ref': offlineRef,
      'status': orderData['status'] ?? 'pending',
    };
  }

  /// POST JSON `/orders` dengan fallback antrian offline.
  static Future<CsOrderSubmitResult> submitJsonOrder({
    required Map<String, dynamic> orderData,
    required Map<String, dynamic> fakturOverlay,
  }) async {
    try {
      final outcome = await OfflineWriteService.postJson(
        path: '/orders',
        body: orderData,
        queueType: 'order',
      );

      if (outcome.queuedOffline) {
        final ref = (outcome.idempotencyKey ?? '').length >= 6
            ? outcome.idempotencyKey!.substring(
                outcome.idempotencyKey!.length - 6,
              )
            : '??????';
        final faktur = mergeFakturData(
          orderData: orderData,
          serverOrOverlay: offlineFakturOverlay(
            orderData: fakturOverlay,
            offlineRef: ref,
          ),
        );
        if (outcome.queueItemId != null) {
          await OfflinePendingOrders.save(
            queueItemId: outcome.queueItemId!,
            fakturData: faktur,
            orderPayload: orderData,
          );
        }
        return CsOrderSubmitResult(
          success: true,
          offlineQueued: true,
          fakturData: faktur,
          offlineRef: ref,
          queueItemId: outcome.queueItemId,
        );
      }

      final response = outcome.response!;
      if (response.statusCode != 200 && response.statusCode != 201) {
        return CsOrderSubmitResult(
          success: false,
          offlineQueued: false,
          errorMessage: response.body,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const CsOrderSubmitResult(
          success: false,
          offlineQueued: false,
          errorMessage: 'Respons order tidak valid',
        );
      }
      final data = Map<String, dynamic>.from(decoded);
      final faktur = mergeFakturData(
        orderData: orderData,
        serverOrOverlay: data,
        extra: fakturOverlay,
      );
      return CsOrderSubmitResult(
        success: true,
        offlineQueued: false,
        serverData: data,
        fakturData: faktur,
      );
    } catch (e) {
      return CsOrderSubmitResult(
        success: false,
        offlineQueued: false,
        errorMessage: e.toString(),
      );
    }
  }

  static void showOfflineQueuedSnackBar(
    BuildContext context, {
    required String offlineRef,
    String? dpNote,
  }) {
    final parts = <String>[
      'Order disimpan offline (ref …$offlineRef). '
      'Akan dikirim otomatis saat koneksi kembali.',
    ];
    if (dpNote != null && dpNote.isNotEmpty) parts.add(dpNote);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(parts.join(' ')),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.orange.shade800,
      ),
    );
  }
}
