import 'package:cloud_firestore/cloud_firestore.dart';
class PorkiUser {
  final String id;
  final String username;
  final String email;
  final String role; // 'admin' o 'colaborador'
  final DateTime createdAt;
  final bool isActive;

  PorkiUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.createdAt,
    this.isActive = true,
  });

  factory PorkiUser.fromMap(Map<String, dynamic> map, String id) {
    return PorkiUser(
      id: id,
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'colaborador',
      createdAt: map['createdAt'] != null 
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      isActive: map['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'email': email,
      'role': role,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
    };
  }

  // Métodos helper para verificar roles
  bool get isAdmin => role == 'admin';
  bool get isColaborador => role == 'colaborador';
  
  // Permisos - AMBOS ROLES TIENEN LOS MISMOS PERMISOS
  bool get canManageUsers => isAdmin; // Solo admin gestiona usuarios
  bool get canDeleteRecords => true; // Ambos pueden eliminar
  bool get canEditAllData => true; // Ambos pueden editar
  bool get canAddRecords => true; // Ambos pueden agregar
  bool get canViewData => true; // Ambos pueden ver
  
  // La única diferencia: solo admin puede gestionar usuarios
}