import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Parent Alert Modal - Displays emergency alert details to parent accounts
///
/// Shows when a child account presses the panic button, displaying:
/// - Alert type (CRITICAL, REGULAR, CANCEL)
/// - Child's name
/// - Date and time (12-hour format)
/// - Location address
/// - Action buttons (Call, View Map, Dismiss)
class ParentAlertModal extends StatelessWidget {
  final String alertType;
  final String childName;
  final String formattedDate;
  final String formattedTime;
  final String address;
  final double? latitude;
  final double? longitude;
  final String childPhone;
  final VoidCallback? onDismiss;

  const ParentAlertModal({
    super.key,
    required this.alertType,
    required this.childName,
    required this.formattedDate,
    required this.formattedTime,
    required this.address,
    this.latitude,
    this.longitude,
    required this.childPhone,
    this.onDismiss,
  });

  /// Get alert-specific color
  Color get _alertColor {
    switch (alertType.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFDC143C); // Crimson red
      case 'REGULAR':
        return const Color(0xFFFF9800); // Orange
      case 'CANCEL':
        return const Color(0xFF4CAF50); // Green
      default:
        return const Color(0xFF757575); // Gray
    }
  }

  /// Get alert-specific icon
  IconData get _alertIcon {
    switch (alertType.toUpperCase()) {
      case 'CRITICAL':
        return Icons.emergency;
      case 'REGULAR':
        return Icons.warning_amber;
      case 'CANCEL':
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }

  /// Get alert-specific title
  String get _alertTitle {
    switch (alertType.toUpperCase()) {
      case 'CRITICAL':
        return 'CRITICAL EMERGENCY';
      case 'REGULAR':
        return 'Emergency Alert';
      case 'CANCEL':
        return 'Alert Cancelled';
      default:
        return 'Alert';
    }
  }

  /// Get alert-specific message
  String get _alertMessage {
    switch (alertType.toUpperCase()) {
      case 'CRITICAL':
        return '$childName needs immediate help!';
      case 'REGULAR':
        return '$childName pressed the panic button';
      case 'CANCEL':
        return '$childName cancelled the emergency';
      default:
        return '$childName sent an alert';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Alert Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _alertColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _alertIcon,
                size: 45,
                color: _alertColor,
              ),
            ),
            const SizedBox(height: 16),

            // Alert Type
            Text(
              _alertTitle,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _alertColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Alert Message
            Text(
              _alertMessage,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Alert Details Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildDetailRow(Icons.person, 'Name', childName),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.calendar_today, 'Date', formattedDate),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.access_time, 'Time', formattedTime),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.location_on,
                    'Location',
                    address.isNotEmpty ? address : 'Location updating...',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            if (alertType.toUpperCase() != 'CANCEL') ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _makePhoneCall(childPhone),
                      icon: const Icon(Icons.call, color: Colors.white),
                      label: const Text(
                        'Call Now',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: latitude != null && longitude != null
                          ? () => _openMap(context)
                          : null,
                      icon: const Icon(Icons.map, color: Colors.white),
                      label: const Text(
                        'View Map',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _alertColor,
                        disabledBackgroundColor: Colors.grey.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Dismiss Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  onDismiss?.call();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  alertType.toUpperCase() == 'CANCEL' ? 'OK' : 'Dismiss',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build detail row widget
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Make phone call
  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      debugPrint('⚠️ No phone number available');
      return;
    }

    try {
      final url = Uri.parse('tel:$phoneNumber');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
        debugPrint('📞 Calling $phoneNumber');
      } else {
        debugPrint('❌ Cannot launch phone dialer');
      }
    } catch (e) {
      debugPrint('❌ Error making phone call: $e');
    }
  }

  /// Open map with location
  Future<void> _openMap(BuildContext context) async {
    if (latitude == null || longitude == null) {
      debugPrint('⚠️ No location available');
      return;
    }

    try {
      // Try Google Maps first (works on both platforms)
      final googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      );

      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
        debugPrint('🗺️ Opened location in Google Maps');
      } else {
        // Fallback to generic geo URL
        final geoUrl =
            Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude');
        if (await canLaunchUrl(geoUrl)) {
          await launchUrl(geoUrl);
          debugPrint('🗺️ Opened location in default map app');
        } else {
          debugPrint('❌ Cannot launch map application');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot open map application'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error opening map: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening map: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
