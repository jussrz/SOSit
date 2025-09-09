import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'settings_page.dart';

class PoliceDashboard extends StatefulWidget {
  const PoliceDashboard({super.key});

  @override
  State<PoliceDashboard> createState() => _PoliceDashboardState();
}

class _PoliceDashboardState extends State<PoliceDashboard> {
  final supabase = Supabase.instance.client;
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isCardExpanded = false;
  List<Map<String, dynamic>> _incidents = [];
  bool _isLoadingIncidents = false;
  String _profilePhotoUrl = '';
  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _incidentHistory = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadIncidents();
    _loadUserProfile();
    _loadIncidentHistory();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
      });

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 14.0,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final userData =
            await supabase.from('user').select().eq('id', userId).single();
        setState(() {
          _profilePhotoUrl = userData['profile_photo_url'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadIncidents() async {
    setState(() => _isLoadingIncidents = true);

    try {
      // Load recent incidents/emergency reports
      final incidents = await supabase
          .from('emergency_reports')
          .select('*, user!inner(*)')
          .order('created_at', ascending: false)
          .limit(10);

      Set<Marker> markers = {};

      for (var incident in incidents) {
        if (incident['latitude'] != null && incident['longitude'] != null) {
          markers.add(
            Marker(
              markerId: MarkerId(incident['id'].toString()),
              position: LatLng(
                incident['latitude'].toDouble(),
                incident['longitude'].toDouble(),
              ),
              infoWindow: InfoWindow(
                title: 'Emergency Report',
                snippet: incident['emergency_type'] ?? 'Unknown',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
            ),
          );
        }
      }

      setState(() {
        _incidents = incidents;
        _markers = markers;
        _isLoadingIncidents = false;
      });
    } catch (e) {
      setState(() => _isLoadingIncidents = false);
      debugPrint('Error loading incidents: $e');
    }
  }

  Future<void> _loadIncidentHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Load incidents where this police responded
      final history = await supabase
          .from('incident_responses')
          .select('*, incident:emergency_reports(*, user!inner(email))')
          .eq('responder_id', userId)
          .order('responded_at', ascending: false)
          .limit(20);

      setState(() {
        _incidentHistory = history;
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() => _isLoadingHistory = false);
      debugPrint('Error loading incident history: $e');
    }
  }

  Future<void> _respondToIncident(
      String incidentId, String responseType) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('incident_responses').insert({
        'incident_id': incidentId,
        'responder_id': userId,
        'response_type': responseType,
        'responded_at': DateTime.now().toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Response recorded: $responseType'),
          backgroundColor: Colors.green,
        ),
      );

      _loadIncidents(); // Refresh incidents
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to record response: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showIncidentHistoryDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: screenWidth * 0.85,
            height: screenHeight * 0.65,
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history,
                        color: Colors.blue, size: screenWidth * 0.07),
                    SizedBox(width: screenWidth * 0.02),
                    Text(
                      'Incident History',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.045,
                        color: Colors.black,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(height: screenHeight * 0.01),
                Expanded(
                  child: _isLoadingHistory
                      ? Center(child: CircularProgressIndicator())
                      : _incidentHistory.isEmpty
                          ? Center(
                              child: Text(
                                'No incident history found.',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: screenWidth * 0.035,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _incidentHistory.length,
                              itemBuilder: (context, index) {
                                final item = _incidentHistory[index];
                                final incident = item['incident'] ?? {};
                                final type =
                                    incident['emergency_type'] ?? 'Unknown';
                                final location = incident['location'] ??
                                    'Location not available';
                                final reporter =
                                    incident['user']?['email'] ?? 'Unknown';
                                final responseType =
                                    item['response_type'] ?? '';
                                final respondedAt = item['responded_at'] != null
                                    ? DateTime.tryParse(item['responded_at'])
                                    : null;
                                final timeAgo = respondedAt != null
                                    ? _getTimeAgo(respondedAt)
                                    : '';

                                return Container(
                                  margin: EdgeInsets.only(
                                      bottom: screenHeight * 0.012),
                                  padding: EdgeInsets.all(screenWidth * 0.03),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.warning,
                                              color: Colors.red,
                                              size: screenWidth * 0.05),
                                          SizedBox(width: screenWidth * 0.02),
                                          Text(
                                            type.toUpperCase(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade700,
                                              fontSize: screenWidth * 0.037,
                                            ),
                                          ),
                                          Spacer(),
                                          Text(
                                            responseType.toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w600,
                                              fontSize: screenWidth * 0.032,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: screenHeight * 0.004),
                                      Text(
                                        'Reporter: $reporter',
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.033,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        'Location: $location',
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.033,
                                          color: Colors.black87,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: screenHeight * 0.004),
                                      Text(
                                        timeAgo,
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.03,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(7.0731, 125.6124), // Davao City
              zoom: 14,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            markers: _markers,
            onMapCreated: (controller) => _mapController = controller,
          ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: EdgeInsets.all(screenWidth * 0.04),
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.04,
                  vertical: screenHeight * 0.015,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Settings
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ),
                      child: Icon(
                        Icons.settings,
                        color: const Color(0xFF2196F3),
                        size: screenWidth * 0.07,
                      ),
                    ),

                    // Police Badge and Title
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_police,
                            color: const Color(0xFF2196F3),
                            size: screenWidth * 0.06,
                          ),
                          SizedBox(width: screenWidth * 0.02),
                          Text(
                            'Police Dashboard',
                            style: TextStyle(
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // History Icon (incident history) - bigger and same color as settings
                    GestureDetector(
                      onTap: _showIncidentHistoryDialog,
                      child: Icon(
                        Icons.history,
                        color: const Color(0xFF2196F3),
                        size: screenWidth * 0.07, // same as settings icon
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: _isCardExpanded ? 0 : screenHeight * 0.03,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.delta.dy < -5 && !_isCardExpanded) {
                  setState(() => _isCardExpanded = true);
                } else if (details.delta.dy > 5 && _isCardExpanded) {
                  setState(() => _isCardExpanded = false);
                }
              },
              onTap: () => setState(() => _isCardExpanded = !_isCardExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isCardExpanded ? screenHeight * 0.6 : null,
                constraints: _isCardExpanded
                    ? null
                    : BoxConstraints(
                        maxHeight: screenHeight * 0.3,
                        minHeight: screenHeight * 0.15,
                      ),
                margin: EdgeInsets.symmetric(
                  horizontal: _isCardExpanded ? 0 : screenWidth * 0.04,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_isCardExpanded ? 24 : 20),
                    topRight: Radius.circular(_isCardExpanded ? 24 : 20),
                    bottomLeft: Radius.circular(_isCardExpanded ? 0 : 20),
                    bottomRight: Radius.circular(_isCardExpanded ? 0 : 20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: _isCardExpanded
                    ? _buildExpandedPanel(screenWidth, screenHeight)
                    : _buildCollapsedPanel(screenWidth, screenHeight),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedPanel(double screenWidth, double screenHeight) {
    return Padding(
      padding: EdgeInsets.all(screenWidth * 0.045),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: screenWidth * 0.12,
            height: 4,
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title and status
          Row(
            children: [
              Icon(
                Icons.local_police,
                color: const Color(0xFF2196F3),
                size: screenWidth * 0.06,
              ),
              SizedBox(width: screenWidth * 0.03),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Incidents',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: screenWidth * 0.045,
                    ),
                  ),
                  Text(
                    '${_incidents.length} reports',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: screenWidth * 0.035,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.03,
                  vertical: screenHeight * 0.005,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'ON DUTY',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: screenWidth * 0.03,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: screenHeight * 0.015),

          // Swipe up indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.keyboard_arrow_up,
                color: Colors.grey.shade600,
                size: screenWidth * 0.05,
              ),
              SizedBox(width: screenWidth * 0.02),
              Text(
                'Swipe up to view incidents',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: screenWidth * 0.03,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedPanel(double screenWidth, double screenHeight) {
    return Padding(
      padding: EdgeInsets.all(screenWidth * 0.045),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: screenWidth * 0.12,
            height: 4,
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Row(
            children: [
              Text(
                'Emergency Reports',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: screenWidth * 0.045,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadIncidents,
                icon: Icon(
                  Icons.refresh,
                  color: const Color(0xFF2196F3),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                color: Colors.grey.shade600,
                size: screenWidth * 0.05,
              ),
            ],
          ),

          SizedBox(height: screenHeight * 0.015),

          // Incidents list
          Expanded(
            child: _isLoadingIncidents
                ? const Center(child: CircularProgressIndicator())
                : _incidents.isEmpty
                    ? _buildEmptyState(screenWidth, screenHeight)
                    : ListView.builder(
                        itemCount: _incidents.length,
                        itemBuilder: (context, index) {
                          final incident = _incidents[index];
                          return _buildIncidentCard(
                              incident, screenWidth, screenHeight);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(double screenWidth, double screenHeight) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.security,
            size: screenWidth * 0.15,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: screenHeight * 0.02),
          Text(
            'No Active Incidents',
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          Text(
            'All clear in your area',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentCard(
      Map<String, dynamic> incident, double screenWidth, double screenHeight) {
    final user = incident['user'];
    final emergencyType = incident['emergency_type'] ?? 'Unknown';
    final location = incident['location'] ?? 'Location not available';
    final timestamp = DateTime.parse(incident['created_at']);
    final timeAgo = _getTimeAgo(timestamp);

    return Container(
      margin: EdgeInsets.only(bottom: screenHeight * 0.015),
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(screenWidth * 0.02),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning,
                  color: Colors.red.shade700,
                  size: screenWidth * 0.05,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emergencyType.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.04,
                        color: Colors.red.shade700,
                      ),
                    ),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.025,
                  vertical: screenHeight * 0.005,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'PENDING',
                  style: TextStyle(
                    fontSize: screenWidth * 0.025,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: screenHeight * 0.01),

          // Details
          Text(
            'Reporter: ${user['email'] ?? 'Unknown'}',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: screenHeight * 0.005),
          Text(
            'Location: $location',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          SizedBox(height: screenHeight * 0.015),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.01),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _respondToIncident(
                    incident['id'].toString(),
                    'dispatched',
                  ),
                  child: Text(
                    'Dispatch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenWidth * 0.035,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.02),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.01),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _respondToIncident(
                    incident['id'].toString(),
                    'responding',
                  ),
                  child: Text(
                    'Respond',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenWidth * 0.035,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

String _getTimeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inDays > 0) {
    return '${difference.inDays}d ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}h ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}m ago';
  } else {
    return 'Just now';
  }
}
