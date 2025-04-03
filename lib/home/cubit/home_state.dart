part of 'home_cubit.dart';

@freezed
class HomeState with _$HomeState {
  const factory HomeState.initial() = _Initial;
  const factory HomeState.loading() = _Loading;
  const factory HomeState.data(String data) = _Data;
  const factory HomeState.connectionStatus(bool isConnected) = _ConnectionStatus;
  const factory HomeState.deviceInfo(Map<String, String> deviceInfo) = _DeviceInfo;
  const factory HomeState.error(String message) = _Error;
  const factory HomeState.log(String log) = _Log;
}
