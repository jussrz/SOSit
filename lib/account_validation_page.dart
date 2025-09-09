import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountValidationPage extends StatefulWidget {
  const AccountValidationPage({super.key});

  @override
  State<AccountValidationPage> createState() => _AccountValidationPageState();
}

class _AccountValidationPageState extends State<AccountValidationPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> pendingAccounts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingAccounts();
  }

  Future<void> _loadPendingAccounts() async {
    setState(() => isLoading = true);

    try {
      // Load pending tanod accounts
      final tanodData = await supabase
          .from('tanod')
          .select('*, user!inner(*)')
          .eq('status', 'pending');

      // Load pending police accounts
      final policeData = await supabase
          .from('police')
          .select('*, user!inner(*)')
          .eq('status', 'pending');

      List<Map<String, dynamic>> allPending = [];

      // Process tanod accounts
      for (var tanod in tanodData) {
        allPending.add({
          'id': tanod['id'],
          'user_id': tanod['user_id'],
          'type': 'tanod',
          'status': tanod['status'],
          'id_number': tanod['id_number'],
          'credentials_url': tanod['credentials_url'],
          'created_at': tanod['created_at'],
          'user': tanod['user'],
        });
      }

      // Process police accounts
      for (var police in policeData) {
        allPending.add({
          'id': police['id'],
          'user_id': police['user_id'],
          'type': 'police',
          'status': police['status'],
          'station_name': police['station_name'],
          'credentials_url': police['credentials_url'],
          'created_at': police['created_at'],
          'user': police['user'],
        });
      }

      // Sort by creation date (newest first)
      allPending.sort((a, b) => DateTime.parse(b['created_at'])
          .compareTo(DateTime.parse(a['created_at'])));

      setState(() {
        pendingAccounts = allPending;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('Error loading pending accounts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load pending accounts: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Colors.black, size: screenWidth * 0.06),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          'Account Validation',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w500,
            fontSize: screenWidth * 0.045,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: const Color(0xFFF73D5C)),
            onPressed: _loadPendingAccounts,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : pendingAccounts.isEmpty
              ? _buildEmptyState(screenWidth, screenHeight)
              : _buildPendingList(screenWidth, screenHeight),
    );
  }

  Widget _buildEmptyState(double screenWidth, double screenHeight) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: screenWidth * 0.2,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: screenHeight * 0.02),
          Text(
            'No Pending Accounts',
            style: TextStyle(
              fontSize: screenWidth * 0.05,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          Text(
            'All accounts have been processed',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingList(double screenWidth, double screenHeight) {
    return RefreshIndicator(
      onRefresh: _loadPendingAccounts,
      child: ListView.builder(
        padding: EdgeInsets.all(screenWidth * 0.04),
        itemCount: pendingAccounts.length,
        itemBuilder: (context, index) {
          final account = pendingAccounts[index];
          return _buildAccountCard(account, screenWidth, screenHeight);
        },
      ),
    );
  }

  Widget _buildAccountCard(
      Map<String, dynamic> account, double screenWidth, double screenHeight) {
    final user = account['user'];
    final accountType = account['type'];
    final createdAt = DateTime.parse(account['created_at']);
    final timeAgo = _getTimeAgo(createdAt);

    return Container(
      margin: EdgeInsets.only(bottom: screenHeight * 0.015),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showAccountDetails(account),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(screenWidth * 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(screenWidth * 0.025),
                    decoration: BoxDecoration(
                      color: accountType == 'tanod'
                          ? Colors.blue.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      accountType == 'tanod'
                          ? Icons.security
                          : Icons.local_police,
                      color:
                          accountType == 'tanod' ? Colors.blue : Colors.green,
                      size: screenWidth * 0.05,
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['email'] ?? 'No email',
                          style: TextStyle(
                            fontSize: screenWidth * 0.04,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.002),
                        Text(
                          accountType.toUpperCase(),
                          style: TextStyle(
                            fontSize: screenWidth * 0.03,
                            color: accountType == 'tanod'
                                ? Colors.blue
                                : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.025,
                          vertical: screenHeight * 0.005,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
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
                      SizedBox(height: screenHeight * 0.005),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: screenWidth * 0.025,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.01),
              Row(
                children: [
                  Text(
                    'Phone: ',
                    style: TextStyle(
                      fontSize: screenWidth * 0.03,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    user['phone'] ?? 'No phone',
                    style: TextStyle(
                      fontSize: screenWidth * 0.03,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              if (accountType == 'tanod' && account['id_number'] != null) ...[
                SizedBox(height: screenHeight * 0.005),
                Row(
                  children: [
                    Text(
                      'ID Number: ',
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      account['id_number'],
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
              if (accountType == 'police' &&
                  account['station_name'] != null) ...[
                SizedBox(height: screenHeight * 0.005),
                Row(
                  children: [
                    Text(
                      'Station: ',
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      account['station_name'],
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountDetails(Map<String, dynamic> account) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountDetailsPage(
          account: account,
          onStatusChanged: _loadPendingAccounts,
        ),
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

class AccountDetailsPage extends StatefulWidget {
  final Map<String, dynamic> account;
  final VoidCallback onStatusChanged;

  const AccountDetailsPage({
    super.key,
    required this.account,
    required this.onStatusChanged,
  });

  @override
  State<AccountDetailsPage> createState() => _AccountDetailsPageState();
}

class _AccountDetailsPageState extends State<AccountDetailsPage> {
  final supabase = Supabase.instance.client;
  bool isProcessing = false;

  Future<void> _updateAccountStatus(String status) async {
    setState(() => isProcessing = true);

    try {
      final table = widget.account['type'];
      final accountId = widget.account['id'];

      await supabase.from(table).update({'status': status}).eq('id', accountId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account ${status.toLowerCase()} successfully!'),
            backgroundColor: status == 'approved' ? Colors.green : Colors.red,
          ),
        );
        widget.onStatusChanged();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final user = widget.account['user'];
    final accountType = widget.account['type'];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Colors.black, size: screenWidth * 0.06),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Account Details',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w500,
            fontSize: screenWidth * 0.045,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(screenWidth * 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account Type Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(screenWidth * 0.04),
              decoration: BoxDecoration(
                color: accountType == 'tanod' ? Colors.blue : Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    accountType == 'tanod'
                        ? Icons.security
                        : Icons.local_police,
                    color: Colors.white,
                    size: screenWidth * 0.12,
                  ),
                  SizedBox(height: screenHeight * 0.01),
                  Text(
                    '${accountType.toUpperCase()} APPLICATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenWidth * 0.04,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: screenHeight * 0.02),

            // User Information
            _buildInfoSection(
                'User Information',
                [
                  _buildInfoRow('Email', user['email'] ?? 'Not provided'),
                  _buildInfoRow('Phone', user['phone'] ?? 'Not provided'),
                  _buildInfoRow('Role', user['role'] ?? 'Not specified'),
                ],
                screenWidth,
                screenHeight),

            SizedBox(height: screenHeight * 0.02),

            // Role-specific Information
            if (accountType == 'tanod')
              _buildInfoSection(
                  'Tanod Information',
                  [
                    _buildInfoRow('ID Number',
                        widget.account['id_number'] ?? 'Not provided'),
                    _buildInfoRow(
                        'Status', widget.account['status'] ?? 'Unknown'),
                  ],
                  screenWidth,
                  screenHeight),

            if (accountType == 'police')
              _buildInfoSection(
                  'Police Information',
                  [
                    _buildInfoRow('Station Name',
                        widget.account['station_name'] ?? 'Not provided'),
                    _buildInfoRow(
                        'Status', widget.account['status'] ?? 'Unknown'),
                  ],
                  screenWidth,
                  screenHeight),

            SizedBox(height: screenHeight * 0.02),

            // Credentials
            if (widget.account['credentials_url'] != null)
              _buildCredentialsSection(screenWidth, screenHeight),

            SizedBox(height: screenHeight * 0.04),

            // Action Buttons
            if (widget.account['status'] == 'pending') ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(
                            vertical: screenHeight * 0.015),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isProcessing
                          ? null
                          : () => _updateAccountStatus('declined'),
                      child: isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Decline',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: screenWidth * 0.04,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.04),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.symmetric(
                            vertical: screenHeight * 0.015),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isProcessing
                          ? null
                          : () => _updateAccountStatus('approved'),
                      child: isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Approve',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: screenWidth * 0.04,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children,
      double screenWidth, double screenHeight) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: screenWidth * 0.04,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: screenHeight * 0.015),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(bottom: screenHeight * 0.01),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: screenWidth * 0.25,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: screenWidth * 0.035,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: screenWidth * 0.035,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsSection(double screenWidth, double screenHeight) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Credentials Proof',
              style: TextStyle(
                fontSize: screenWidth * 0.04,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: screenHeight * 0.015),
            Container(
              width: double.infinity,
              height: screenHeight * 0.25,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.account['credentials_url'],
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: screenWidth * 0.1, color: Colors.grey),
                          SizedBox(height: screenHeight * 0.01),
                          Text('Failed to load image',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
