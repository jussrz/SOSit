import 'package:flutter/material.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  // Placeholder group members
  final List<Map<String, dynamic>> _members = [
    {
      'name': 'Juan Dela Cruz',
      'role': 'Owner',
      'relationship': 'Father',
      'phone': '+63 912 345 6789',
      'email': 'juan@email.com',
      'avatar': '',
    },
    {
      'name': 'Maria Santos',
      'role': 'Emergency Contact',
      'relationship': 'Mother',
      'phone': '+63 922 123 4567',
      'email': 'maria@email.com',
      'avatar': '',
    },
    {
      'name': 'Jose Rizal',
      'role': 'Emergency Contact',
      'relationship': 'Sibling',
      'phone': '+63 933 987 6543',
      'email': 'jose@email.com',
      'avatar': '',
    },
  ];

  Map<String, dynamic>? _selectedMember;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Group Members', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(screenWidth * 0.05),
              itemCount: _members.length,
              itemBuilder: (context, index) {
                final member = _members[index];
                return Container(
                  margin: EdgeInsets.only(bottom: screenHeight * 0.015),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFF73D5C).withOpacity(0.13),
                      child: Icon(Icons.person, color: const Color(0xFFF73D5C)),
                    ),
                    title: Text(member['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${member['role']} - ${member['relationship']}', style: TextStyle(color: Colors.grey.shade700)),
                    onTap: () {
                      setState(() {
                        _selectedMember = member;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          if (_selectedMember != null)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.05,
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(screenWidth * 0.025),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF73D5C).withOpacity(0.1),
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
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _selectedMember!['name'],
                            style: TextStyle(
                              fontSize: screenWidth * 0.04,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.002),
                          Text(
                            '${_selectedMember!['role']} - ${_selectedMember!['relationship']}',
                            style: TextStyle(
                              fontSize: screenWidth * 0.035,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.002),
                          Text(
                            _selectedMember!['phone'],
                            style: TextStyle(
                              fontSize: screenWidth * 0.035,
                              color: const Color(0xFF2196F3),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.002),
                          Text(
                            _selectedMember!['email'],
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
    );
  }
}
