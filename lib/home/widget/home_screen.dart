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
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: const Text(
              'Zanis Data Communication',
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: _buildBody(),
        ),
      );

  Widget _buildBody() => Column(
        children: [
          Expanded(
            child: BlocBuilder<HomeCubit, HomeState>(
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
                    data: (value) => _buildDataView(value),
                    error: (message) => Center(child: Text(message)),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    orElse: () => const Center(
                      child: Text(
                        'Waiting for data...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 3,
            child: _buildLogView(),
          ),
        ],
      );

  Widget _buildDataView(String value) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Data:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Widget _buildLogView() => BlocBuilder<HomeCubit, HomeState>(
        buildWhen: (previous, current) => current.whenOrNull(logs: (value) => true) ?? false,
        builder: (context, state) {
          final logs = state.maybeWhen(
            logs: (value) => value,
            orElse: () => <String>[],
          );
          return Container(
            color: Colors.black,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              reverse: false,
              shrinkWrap: true,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return Text(
                  log,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Monospace',
                    fontSize: 12,
                  ),
                );
              },
            ),
          );
        },
      );
}
