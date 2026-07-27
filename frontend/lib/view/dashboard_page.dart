import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/blockchain_service.dart'; // Importante: subimos un nivel para buscar 'core'
import 'package:qr_flutter/qr_flutter.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final BlockchainService _blockchain = BlockchainService();
  final String _testAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
  String _balance = "0.00";
  bool _isLoading = false;
  bool _isServiceReady = false;
  bool _showQrInCircle = false;
  Timer? _qrHideTimer;

  @override
  void initState() {
    super.initState();
    _setupBlockchain();
  }

  Future<void> _setupBlockchain() async {
    setState(() => _isLoading = true);
    await _blockchain.init(); // <--- Carga el ABI
    setState(() {
      _isServiceReady = true;
    });
    await _refreshBalance(); // <--- Ahora sí pide el balance
  }

  Future<void> _refreshBalance() async {
    if (!_isServiceReady) return;

    setState(() => _isLoading = true);
    try {
      // Asegúrate de usar la dirección que tiene los tokens en Anvil
      final bal = await _blockchain.getViaBalance(
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
      );
      setState(() {
        _balance = bal.toStringAsFixed(2);
      });
    } catch (e) {
      print("Error visualizando balance: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _payPassport() async {
    setState(() => _isLoading = true);

    // DATOS DE PRUEBA (Esto luego vendrá del QR y del SecureStorage)
    const String testPrivKey =
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    const String busOperatorAddress =
        "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; // Cuenta 2 de Anvil

    String txHash = await _blockchain.transferVia(
      testPrivKey,
      busOperatorAddress,
      2.50, // Precio del pasaje
    );

    if (txHash.isNotEmpty) {
      // Si la transacción fue exitosa, actualizamos el saldo
      await _refreshBalance();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("¡Pago de pasaje exitoso!")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al procesar el pago")),
      );
    }

    setState(() => _isLoading = false);
  }

  void _showQrTemporarily() {
    _qrHideTimer?.cancel();
    setState(() => _showQrInCircle = true);

    _qrHideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _showQrInCircle = false);
    });
  }

  @override
  void dispose() {
    _qrHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "VIA NETWORK",
                style: GoogleFonts.orbitron(
                  letterSpacing: 10,
                  fontSize: 16,
                  color: Colors.white24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _showQRButton(context),
              const SizedBox(height: 60),
              _balanceDisplay(), // He extraído esto a un método abajo para mayor claridad
              const SizedBox(height: 80),
              _actionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  // Métodos de ayuda para que el 'build' no sea tan largo
  Widget _balanceDisplay() {
    return Container(
      width: 280,
      height: 280,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: _showQrInCircle
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "ESCANEE EN EL BUS",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      letterSpacing: 1.5,
                      fontSize: 10,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 12),
                  QrImageView(
                    data: _testAddress,
                    version: QrVersions.auto,
                    size: 118,
                    gapless: false,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.white,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "BALANCE DISPONIBLE",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(height: 15),
                  _isLoading
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        )
                      : Text(
                          "$_balance VIA",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w200,
                            color: Colors.white,
                          ),
                        ),
                ],
              ),
      ),
    );
  }

  Widget _actionButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 55,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _refreshBalance,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white10),
              ),
              icon: const Icon(Icons.refresh_outlined, color: Colors.white),
              label: const Text(
                "ACTUALIZAR",
                style: TextStyle(color: Colors.white, letterSpacing: 1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 55,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _payPassport,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white10),
              ),
              icon: const Icon(Icons.payment_outlined, color: Colors.white),
              label: const Text(
                "PAGAR",
                style: TextStyle(color: Colors.white, letterSpacing: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _showQRButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        _showQrTemporarily();
      },
      icon: const Icon(Icons.qr_code_2, color: Colors.white),
      label: const Text("MOSTRAR QR", style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent, // Resalta sobre el fondo negro
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        elevation: 15,
      ),
    );
  }
}
