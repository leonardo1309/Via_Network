import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'view/dashboard_page.dart'; // Importamos la nueva ubicación de la página

void main() {
  runApp(const ViaNetworkApp());
}

class ViaNetworkApp extends StatelessWidget {
  const ViaNetworkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VIA Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
      ),
      // Aquí simplemente llamamos a la clase que ahora vive en otro archivo
      home: const DashboardPage(), 
    );
  }
}