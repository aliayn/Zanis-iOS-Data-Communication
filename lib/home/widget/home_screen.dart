import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zanis_ios_data_communication/di/injection.dart';
import 'package:zanis_ios_data_communication/home/cubit/home_cubit.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
      create: (context) => inject<HomeCubit>(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Zanis Data Communication'),
        ),
        body: _buildBody(),
      ),
    );

  Widget _buildBody() => BlocBuilder<HomeCubit, HomeState>(
      buildWhen: (previous, current) =>
          current.whenOrNull(
            data: (value) => true,
            error: (message) => true,
            loading: () => true,
          ) ??
          false,
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: state.maybeWhen(
            data: (value) => Center(child: Text(value)),
            error: (message) => Center(child: Text(message)),
            loading: () => const Center(child: CircularProgressIndicator()),
            orElse: () => const Center(child: Text('Waiting for data...')),
          ),
        );
      },
    );
}
