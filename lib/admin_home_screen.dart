import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'admin_settings_page.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;
  final int _numTabs = 3;

  bool _isLoading = false;
  String _adminName = '';

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  bool _obscurePassword = true;
  String? _selectedRole;
  File? _proofFile;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  // Tanod fields
  final _idNumberController = TextEditingController();

  // Police fields
  final _stationNameController = TextEditingController();

  // Users tab state
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  String _userRoleFilter = 'all';
  String _userNameFilter = '';

  // Add state for selected user
  Map<String, dynamic>? _selectedUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _numTabs, vsync: this);
    _loadAdminData();
    _loadAllUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _idNumberController.dispose();
    _stationNameController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final adminData = await supabase
            .from('admin')
            .select('admin_firstname, admin_lastname')
            .eq('id', userId)
            .single();

        setState(() {
          _adminName =
              '${adminData['admin_firstname']} ${adminData['admin_lastname']}';
        });
      }
    } catch (e) {
      debugPrint('Error loading admin data: $e');
    }
  }

  Future<void> _pickProofFile() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      setState(() {
        _proofFile = File(image.path);
      });
    }
  }

  Future<void> _createAccount() async {
    setState(() {
      _submitted = true;
    });

    if (!_formKey.currentState!.validate() || _selectedRole == null) {
      if (_selectedRole == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a role')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Create auth account in Supabase
      final res = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user == null) throw Exception('Failed to create user');

      final userId = res.user!.id;
      final email = _emailController.text.trim(); // Store email for reuse

      // 2. Insert into user table
      await supabase.from('user').insert({
        'id': userId,
        'email': email,
        'phone': _phoneController.text.trim(),
        'role': _selectedRole,
      });

      // 3. Insert into specific role table
      if (_selectedRole == 'tanod') {
        String? proofUrl;
        if (_proofFile != null) {
          final fileBytes = await _proofFile!.readAsBytes();
          final filePath = 'tanod_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await supabase.storage
              .from('credentials_proof')
              .uploadBinary(filePath, fileBytes);
          proofUrl =
              supabase.storage.from('credentials_proof').getPublicUrl(filePath);
        }

        await supabase.from('tanod').insert({
          'user_id': userId,
          'email': email, // Add email to tanod table
          'id_number': _idNumberController.text.trim().isNotEmpty
              ? _idNumberController.text.trim()
              : null,
          'credentials_url': proofUrl,
          'status': 'approved',
        });
      } else if (_selectedRole == 'police') {
        String? proofUrl;
        if (_proofFile != null) {
          final fileBytes = await _proofFile!.readAsBytes();
          final filePath =
              'police_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await supabase.storage
              .from('credentials_proof')
              .uploadBinary(filePath, fileBytes);
          proofUrl =
              supabase.storage.from('credentials_proof').getPublicUrl(filePath);
        }

        await supabase.from('police').insert({
          'user_id': userId,
          'email': email, // Add email to police table
          'station_name': _stationNameController.text.trim().isNotEmpty
              ? _stationNameController.text.trim()
              : null,
          'credentials_url': proofUrl,
          'status': 'approved',
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${_selectedRole!.toUpperCase()} account created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      _clearForm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    _emailController.clear();
    _passwordController.clear();
    _phoneController.clear();
    _idNumberController.clear();
    _stationNameController.clear();
    setState(() {
      _selectedRole = null;
      _proofFile = null;
      _submitted = false;
    });
  }

  // Validators
  String? _validateRequired(String? value) =>
      (value == null || value.isEmpty) ? 'This field is required' : null;

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Enter an email';
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!regex.hasMatch(value)) return 'Enter a valid email format';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'Phone number is required';
    String cleanedValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanedValue.length != 11) return 'Phone number must be 11 digits';
    if (!cleanedValue.startsWith('09')) {
      return 'Phone number must start with 09';
    }
    return null;
  }

  Future<void> _loadAllUsers() async {
    setState(() => _isLoading = true);
    try {
      // Load all users from the user table
      final users = await supabase
          .from('user')
          .select(
              'id, first_name, middle_name, last_name, birthdate, phone, email, role, created_at')
          .order('created_at', ascending: false);

      debugPrint('Supabase user query result: $users');
      debugPrint('Type of users: ${users.runtimeType}');
      debugPrint('Is users a List? ${users is List}');
      debugPrint(
          'Number of users loaded: ${users is List ? users.length : 'not a list'}');

      setState(() {
        // Defensive: ensure _allUsers is always a List<Map<String, dynamic>>
        if (users.isNotEmpty) {
          _allUsers = List<Map<String, dynamic>>.from(users);
        } else {
          _allUsers = [];
        }
        _applyUserFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading users: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e')),
        );
      }
    }
  }

  void _applyUserFilters() {
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        final matchesRole =
            _userRoleFilter == 'all' || user['role'] == _userRoleFilter;
        final name = [
          user['first_name'] ?? '',
          user['middle_name'] ?? '',
          user['last_name'] ?? ''
        ].join(' ').toLowerCase();
        final matchesName = _userNameFilter.isEmpty ||
            name.contains(_userNameFilter.toLowerCase());
        return matchesRole && matchesName;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings,
                color: const Color(0xFFF73D5C), size: screenWidth * 0.07),
            SizedBox(width: screenWidth * 0.03),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin Dashboard',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: screenWidth * 0.045,
                    ),
                  ),
                  if (_adminName.isNotEmpty)
                    Text(
                      'Welcome, $_adminName',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: screenWidth * 0.035,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.settings,
                  color: const Color(0xFFF73D5C), size: screenWidth * 0.06),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminSettingsPage()),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFF73D5C),
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: const Color(0xFFF73D5C),
          tabs: const [
            Tab(
              icon: Icon(Icons.security),
              text: 'Add Tanod',
            ),
            Tab(
              icon: Icon(Icons.local_police),
              text: 'Add Police',
            ),
            Tab(
              icon: Icon(Icons.people),
              text: 'Users',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAddAccountForm('tanod'),
          _buildAddAccountForm('police'),
          _buildUsersTab(),
        ],
      ),
    );
  }

  Widget _buildAddAccountForm(String type) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return SingleChildScrollView(
      padding: EdgeInsets.all(screenWidth * 0.04),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(screenWidth * 0.04),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    type == 'tanod' ? Icons.security : Icons.local_police,
                    size: screenWidth * 0.15,
                    color: const Color(0xFFF73D5C),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Text(
                    'Add New ${type.toUpperCase()}',
                    style: TextStyle(
                      fontSize: screenWidth * 0.055,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    'Create a new $type account',
                    style: TextStyle(
                      fontSize: screenWidth * 0.035,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: screenHeight * 0.03),

            // Email Field
            _buildFormField(
              controller: _emailController,
              hint: 'Email',
              icon: Icons.email,
              validator: _validateEmail,
              keyboardType: TextInputType.emailAddress,
            ),

            SizedBox(height: screenHeight * 0.02),

            // Phone Field
            _buildFormField(
              controller: _phoneController,
              hint: 'Phone Number',
              icon: Icons.phone,
              validator: _validatePhone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
            ),

            SizedBox(height: screenHeight * 0.02),

            // Password Field
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.lock, color: Colors.grey.shade600),
                      hintText: 'Password',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                      errorStyle: const TextStyle(height: 0),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey.shade600,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    style: TextStyle(fontSize: screenWidth * 0.04),
                  ),
                ),
                if (_submitted) ...[
                  Builder(
                    builder: (context) {
                      final error = _validatePassword(_passwordController.text);
                      if (error != null) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Text(
                            error,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ],
            ),

            SizedBox(height: screenHeight * 0.02),

            // Role-specific fields
            if (type == 'tanod') ...[
              _buildFormField(
                controller: _idNumberController,
                hint: 'ID Number',
                icon: Icons.badge,
                validator: _validateRequired,
              ),
            ] else ...[
              _buildFormField(
                controller: _stationNameController,
                hint: 'Station Name',
                icon: Icons.location_city,
                validator: _validateRequired,
              ),
            ],

            SizedBox(height: screenHeight * 0.02),

            // Upload Credentials
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: _pickProofFile,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.upload_file, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Text(
                        _proofFile == null
                            ? 'Upload Credentials Proof (Optional)'
                            : 'Document Selected',
                        style: TextStyle(
                          color: _proofFile == null
                              ? Colors.grey.shade600
                              : Colors.black,
                          fontSize: screenWidth * 0.04,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: screenHeight * 0.04),

            // Create Account Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF73D5C),
                  padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() => _selectedRole = type);
                        _createAccount();
                      },
                child: _isLoading
                    ? const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)
                    : Text(
                        'Create ${type.toUpperCase()} Account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: screenWidth * 0.045,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),

            SizedBox(height: screenHeight * 0.02),

            // Clear Form Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFF73D5C)),
                  padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: _clearForm,
                child: Text(
                  'Clear Form',
                  style: TextStyle(
                    color: const Color(0xFFF73D5C),
                    fontSize: screenWidth * 0.045,
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

  Widget _buildFormField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.grey.shade600),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(vertical: screenHeight * 0.025),
              errorStyle: const TextStyle(height: 0),
            ),
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: TextStyle(fontSize: screenWidth * 0.04),
          ),
        ),
        if (_submitted && validator != null) ...[
          Builder(
            builder: (context) {
              final error = validator(controller.text);
              if (error != null) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildUsersTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(screenWidth * 0.03),
          child: Row(
            children: [
              // Role filter
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                child: DropdownButton<String>(
                  value: _userRoleFilter,
                  underline: SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Roles')),
                    DropdownMenuItem(value: 'citizen', child: Text('Citizen')),
                    DropdownMenuItem(value: 'tanod', child: Text('Tanod')),
                    DropdownMenuItem(value: 'police', child: Text('Police')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _userRoleFilter = val ?? 'all';
                      _applyUserFilters();
                      _selectedUser = null; // Clear selection on filter change
                    });
                  },
                ),
              ),
              SizedBox(width: screenWidth * 0.04),
              // Name filter
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name',
                      prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    ),
                    onChanged: (val) {
                      _userNameFilter = val;
                      _applyUserFilters();
                      _selectedUser = null; // Clear selection on search
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadAllUsers,
                        child: _filteredUsers.isEmpty
                            ? Center(
                                child: Text(
                                  'No users found.',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: screenWidth * 0.04,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.all(screenWidth * 0.02),
                                itemCount: _filteredUsers.length,
                                itemBuilder: (context, index) {
                                  final user = _filteredUsers[index];
                                  final fullName = [
                                    user['first_name'] ?? '',
                                    user['middle_name'] ?? '',
                                    user['last_name'] ?? ''
                                  ].where((n) => n.isNotEmpty).join(' ');
                                  return Card(
                                    margin: EdgeInsets.only(
                                        bottom: screenHeight * 0.012),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: const Color(0xFFF73D5C)
                                            .withOpacity(0.1),
                                        child: Icon(Icons.person,
                                            color: const Color(0xFFF73D5C)),
                                      ),
                                      title: Text(fullName.isNotEmpty
                                          ? fullName
                                          : user['email'] ?? 'No Name'),
                                      subtitle: Text(
                                          'Role: ${user['role'] ?? 'N/A'}'),
                                      onTap: () {
                                        setState(() {
                                          _selectedUser = user;
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    if (_selectedUser != null)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.03,
                          vertical: screenHeight * 0.01,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          padding: EdgeInsets.all(screenWidth * 0.04),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment
                                .center, // <-- Center vertically
                            children: [
                              Container(
                                padding: EdgeInsets.all(screenWidth * 0.025),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFF73D5C).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.person,
                                  color: const Color(0xFFF73D5C),
                                  size: screenWidth * 0.06,
                                ),
                              ),
                              SizedBox(width: screenWidth * 0.04),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment
                                      .center, // <-- Center vertically
                                  children: [
                                    Text(
                                      [
                                        _selectedUser!['first_name'] ?? '',
                                        _selectedUser!['middle_name'] ?? '',
                                        _selectedUser!['last_name'] ?? ''
                                      ].where((n) => n.isNotEmpty).join(' '),
                                      style: TextStyle(
                                        fontSize: screenWidth * 0.04,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                    ),
                                    SizedBox(height: screenHeight * 0.002),
                                    Text(
                                      'Role: ${_selectedUser!['role'] ?? 'N/A'}',
                                      style: TextStyle(
                                        fontSize: screenWidth * 0.035,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    SizedBox(height: screenHeight * 0.002),
                                    if (_selectedUser!['email'] != null)
                                      Text(
                                        _selectedUser!['email'],
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.035,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    if (_selectedUser!['phone'] != null)
                                      Text(
                                        _selectedUser!['phone'],
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.035,
                                          color: const Color(0xFF2196F3),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    if (_selectedUser!['birthdate'] != null)
                                      Text(
                                        'Birthdate: ${_selectedUser!['birthdate']}',
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.035,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    if (_selectedUser!['created_at'] != null)
                                      Text(
                                        'Created: ${_selectedUser!['created_at']}',
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.035,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
