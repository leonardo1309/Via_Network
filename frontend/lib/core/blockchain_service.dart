import 'package:http/http.dart';
import 'package:web3dart/web3dart.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:flutter/services.dart';

class BlockchainService {
  // Para Android Emulator usa esta:
  final String _rpcUrl = "http://10.0.2.2:8545";

  // La dirección que te dio 'forge create'
  final String _contractAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  late DeployedContract _contract;
  late String _abiCode;
  late Web3Client _ethClient;

  BlockchainService() {
    _ethClient = Web3Client(_rpcUrl, Client());
  }

  // Agregamos un método para inicializar el servicio
  Future<void> init() async {
    try {
      // 1. Leemos el archivo desde assets
      _abiCode = await rootBundle.loadString('assets/via_abi.json');

      // 2. Configuramos el contrato de una vez para no repetirlo
      _contract = DeployedContract(
        ContractAbi.fromJson(_abiCode, "VIA"),
        EthereumAddress.fromHex(_contractAddress),
      );
      print("Blockchain Service: ABI cargado correctamente");
    } catch (e) {
      print("Blockchain Service: Error cargando ABI: $e");
    }
  }

  // Función para consultar el saldo de un usuario en VIA Tokens
  Future<double> getViaBalance(String userAddress) async {
    try {
      // 2. Referenciamos la función 'balanceOf' del estándar ERC20
      final contractFunction = _contract.function('balanceOf');

      // 3. Llamamos a la función en la blockchain
      final result = await _ethClient.call(
        contract: _contract,
        function: contractFunction,
        params: [EthereumAddress.fromHex(userAddress)],
      );

      if (result.isNotEmpty) {
        return (result.first as BigInt).toDouble() / 1e18;
      }
      return 0.0;
    } catch (e) {
      print("Error consultando saldo: $e");
      return 0.0;
    }
  }

  Future<String> transferVia(
    String privateKey,
    String toAddress,
    double amount,
  ) async {
    try {
      // 1. Obtenemos las credenciales a partir de la llave privada
      final credentials = EthPrivateKey.fromHex(privateKey);
      //final senderAddress = credentials.address;

      // 2. Localizamos la función 'transfer' en el contrato
      final function = _contract.function('transfer');

      // 3. Convertimos el monto a Wei (18 decimales)
      final BigInt amountInWei = BigInt.from(amount * 1000000000000000000);

      // 4. Enviamos la transacción
      final response = await _ethClient.sendTransaction(
        credentials,
        Transaction.callContract(
          contract: _contract,
          function: function,
          parameters: [EthereumAddress.fromHex(toAddress), amountInWei],
        ),
        chainId: 31337, // ID por defecto de Anvil
      );

      print("Transacción enviada: $response");
      return response; // Devuelve el hash de la transacción
    } catch (e) {
      print("Error en la transferencia: $e");
      return "";
    }
  }
}
