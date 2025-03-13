import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zanis_ios_data_communication/di/injection.dart';
import 'package:zanis_ios_data_communication/home/cubit/home_cubit.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => inject<HomeCubit>(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Home'),
        ),
      ),
    );
  }
}
