import 'package:flutter/material.dart';
import '../../design_system/components/sejilo_input.dart';
import '../../design_system/sejilo_theme.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key, this.onCreate});

  final ValueChanged<String>? onCreate;

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _nameController = TextEditingController();
  final List<_SelectedUser> _selected = [];

  final List<_SelectedUser> _contacts = [
    _SelectedUser(username: 'rahul_99', displayName: 'Rahul'),
    _SelectedUser(username: 'suman_x', displayName: 'Suman'),
    _SelectedUser(username: 'anish_k', displayName: 'Anish'),
    _SelectedUser(username: 'maya.lens', displayName: 'Maya'),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggle(_SelectedUser user) {
    setState(() {
      if (_selected.any((u) => u.username == user.username)) {
        _selected.removeWhere((u) => u.username == user.username);
      } else {
        _selected.add(user);
      }
    });
  }

  void _create() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selected.isEmpty) return;
    widget.onCreate?.call(name);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'New group',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SejiloInput(
                  controller: _nameController,
                  hintText: 'Give your group a name',
                  labelText: 'Group name',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final user = _contacts[index];
                    final selected = _selected.any((u) => u.username == user.username);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: SejiloColors.primary.withValues(alpha: .15),
                        child: Text(user.displayName.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('@${user.username}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: Checkbox(
                        value: selected,
                        onChanged: (_) => _toggle(user),
                      ),
                      onTap: () => _toggle(user),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _nameController.text.trim().isNotEmpty && _selected.isNotEmpty ? _create : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Create group (${_selected.length})',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedUser {
  const _SelectedUser({required this.username, required this.displayName});
  final String username;
  final String displayName;
}
