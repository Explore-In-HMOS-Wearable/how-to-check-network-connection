import { ConnectionDetails,
  ConnectionStatus,
  ConnectionType, NetworkConnectionService } from './NetworkConnectionService';

@Entry
@Component
struct Index {
  private networkService: NetworkConnectionService = NetworkConnectionService.getInstance();
  @State isInitialized: boolean = false;
  @State connectionType: ConnectionType = ConnectionType.UNKNOWN;
  @State connectionStatus: ConnectionStatus = ConnectionStatus.CHECKING;
  @State connectionMessage: string = 'Checking';
  @State isNetworkAccessible: boolean = false;
  @State hasWifi: boolean = false;
  @State hasCellular: boolean = false;

  async aboutToAppear() {
    try {
      await this.networkService.initialize();
      this.isInitialized = true;
      this.networkService.addConnectionStatusListener((details: ConnectionDetails) => {
        this.updateConnectionStatus(details);
      });
      await this.checkConnection();
    } catch (error) {
      console.error('[Index] Init error:', JSON.stringify(error));
      this.connectionMessage = 'Service cannot be started';
    }
  }
  aboutToDisappear() {
    this.networkService.destroy();
  }

  async checkConnection() {
    const details = await this.networkService.checkConnectionStatus();
    this.updateConnectionStatus(details);
  }

  updateConnectionStatus(details: ConnectionDetails) {
    this.connectionStatus = details.status;
    this.connectionMessage = details.message;
    this.isNetworkAccessible = details.isNetworkAccessible;
    this.hasWifi = details.hasWifi;
    this.hasCellular = details.hasCellular;
    this.connectionType = details.connectionType;
  }

  async makeNetworkRequest() {
    const canRequest = await this.networkService.canMakeNetworkRequest();
    if (canRequest) {
      console.info('[Index] Request started');
    } else {
      console.error('[Index] Cannot request:', this.connectionMessage);
    }
  }
  build() {
    Column() {
      Text(this.connectionStatus)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
    }
    .height('100%')
    .width('100%').alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
  }
}