import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';

class Store {
  const Store({
    required this.id,
    required this.name,
    required this.isCentral,
    required this.isActive,
    this.address,
    this.phone,
  });

  factory Store.fromJson(Json json) => Store(
    id: toInt(json['id']),
    name: '${json['name']}',
    address: toStringOrNull(json['address']),
    phone: toStringOrNull(json['phone']),
    isCentral: json['is_central'] == true,
    isActive: json['is_active'] != false,
  );

  final int id;
  final String name;
  final String? address;
  final String? phone;
  final bool isCentral;
  final bool isActive;

  /// Nom affiché : le magasin central est toujours présenté comme « Stock Local ».
  String get label => isCentral ? 'Stock Local' : Formats.capitalize(name);

  StoreRef get ref => StoreRef(id: id, name: name, isCentral: isCentral);
}
