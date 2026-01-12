import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { constant, wifiManager } from '@kit.ConnectivityKit';
import { access } from '@kit.ConnectivityKit';
import { data } from '@kit.TelephonyKit';
import { connection as connect }  from '@kit.ConnectivityKit';

export enum ConnectionStatus {
  CONNECTED = 'CONNECTED',
  DISCONNECTED = 'DISCONNECTED',
  CHECKING = 'CHECKING'
}

export enum ConnectionType {
  WIFI = 'WiFi',
  CELLULAR = 'Cellular',
  BLUETOOTH = 'Bluetooth',
  UNKNOWN = 'Unknown'
}


export interface ConnectionDetails {
  status: ConnectionStatus;
  isNetworkAccessible: boolean;
  hasWifi: boolean;
  hasCellular: boolean;
  hasBluetooth: boolean;
  connectionType: ConnectionType;
  message: string;
}


export class NetworkConnectionService {
  private static instance: NetworkConnectionService;
  private netConnection: connection.NetConnection | undefined = undefined;
  private isInitialized: boolean = false;
  private connectionStatusCallbacks: Array<(details: ConnectionDetails) => void> = [];

  private constructor() {}


  public static getInstance(): NetworkConnectionService {
    if (!NetworkConnectionService.instance) {
      NetworkConnectionService.instance = new NetworkConnectionService();
    }
    return NetworkConnectionService.instance;
  }


  public async initialize(): Promise<void> {
    if (this.isInitialized) {
      console.info('[NetworkService] Already initialized');
      return;
    }

    try {
      this.netConnection = connection.createNetConnection();

      await this.netConnection.register((error: BusinessError) => {
        if (error) {
          console.error('[NetworkService] Register failed:', JSON.stringify(error));
        } else {
          console.info('[NetworkService] Register success');
        }
      });

      this.setupNetworkListeners();

      this.isInitialized = true;
      console.info('[NetworkService] Initialized successfully');

      await this.checkConnectionStatus();
    } catch (error) {
      console.error('[NetworkService] Initialization error:', JSON.stringify(error));
      new Error(error)
    }
  }

  private setupNetworkListeners(): void {
    if (!this.netConnection) {
      return;
    }

    this.netConnection.on('netAvailable', (data: connection.NetHandle) => {
      console.info('[NetworkService] Network available:', JSON.stringify(data));
      this.checkConnectionStatus();
    });

    this.netConnection.on('netUnavailable', () => {
      console.info('[NetworkService] Network unavailable');
      this.checkConnectionStatus();
    });

    this.netConnection.on('netCapabilitiesChange', (data: connection.NetCapabilityInfo) => {
      console.info('[NetworkService] Network capabilities changed');
      this.checkConnectionStatus();
    });

    this.netConnection.on('netConnectionPropertiesChange', (data: connection.NetConnectionPropertyInfo) => {
      console.info('[NetworkService] Connection properties changed');
      this.checkConnectionStatus();
    });

    this.netConnection.on('netLost', (data: connection.NetHandle) => {
      console.info('[NetworkService] Network lost:', JSON.stringify(data));
      this.checkConnectionStatus();
    });
  }


  private isNetworkAccessible(): boolean {
    try {
      let netHandle = connection.getDefaultNetSync();

      if (!netHandle || netHandle.netId < 100) {
        console.info('[NetworkService] Invalid netHandle:', netHandle?.netId);
        return false;
      }

      let netCapability = connection.getNetCapabilitiesSync(netHandle);
      let capabilities = netCapability.networkCap;

      if (!capabilities) {
        console.info('[NetworkService] No network capabilities');
        return false;
      }

      return capabilities.map(cap => connection.NetCap.NET_CAPABILITY_VALIDATED === cap).includes(true);


      return false;
    } catch (error) {
      let err = error as BusinessError;
      console.error('[NetworkService] Error checking network accessibility:', JSON.stringify(err));
      return false;
    }
  }


  private checkWifiConnection(): boolean {
    try {
      const isWifiActive = wifiManager.isWifiActive();
      const isConnected = wifiManager.isConnected();

      if (isWifiActive && isConnected) {
        console.info('[NetworkService] WiFi is connected');
        return true;
      }

      console.info('[NetworkService] WiFi is not connected (active:', isWifiActive, ', connected:', isConnected, ')');
      return false;
    } catch (error) {
      console.error('[NetworkService] WiFi check error:', JSON.stringify(error));
      return false;
    }
  }

  private async checkCellularConnection(): Promise<boolean> {
    try {
      const isCellularEnabled = await data.isCellularDataEnabled();

      if (!isCellularEnabled) {
        console.info('[NetworkService] Cellular data is disabled');
        return false;
      }

      const dataState = await data.getCellularDataState();

      if (dataState === 2) {
        console.info('[NetworkService] Cellular data is connected');
        return true;
      }

      console.info('[NetworkService] Cellular data state:', dataState);
      return false;
    } catch (error) {
      console.error('[NetworkService] Cellular check error:', JSON.stringify(error));
      return false;
    }
  }

  private checkBluetoothConnection(): boolean {
    try {
      const btState  = access.getState();

      if (btState !== 2) {
        console.info('[NetworkService] Bluetooth is not on, state:', btState);
        return false;
      }

      const btConnectionState : connect.ProfileConnectionState =
        connect.getProfileConnectionState(constant.ProfileId.PROFILE_A2DP_SOURCE);

      if (btConnectionState === 2) {
        console.info('[NetworkService] Bluetooth is connected');
        return true;
      }

      console.info('[NetworkService] Bluetooth connection state:', btConnectionState);
      return false;
    } catch (error) {
      console.error('[NetworkService] Bluetooth check error:', JSON.stringify(error));
      return false;
    }
  }

  private getActiveConnectionType(): ConnectionType {
    try {
      let netHandle = connection.getDefaultNetSync();

      if (!netHandle || netHandle.netId < 100) {
        return ConnectionType.UNKNOWN;
      }

      let netCapability = connection.getNetCapabilitiesSync(netHandle);
      let bearerTypes = netCapability.bearerTypes;

      if (!bearerTypes || bearerTypes.length === 0) {
        return ConnectionType.UNKNOWN;
      }

      const bearerType = bearerTypes[0];

      if (bearerType === 1) {
        return ConnectionType.WIFI;
      }
      else if (bearerType === 0) {
        return ConnectionType.CELLULAR;
      }
      else if (bearerType === 2) {
        return ConnectionType.BLUETOOTH;
      }

      return ConnectionType.UNKNOWN;
    } catch (error) {
      console.error('[NetworkService] Error getting connection type:', JSON.stringify(error));
      return ConnectionType.UNKNOWN;
    }
  }


  public async checkConnectionStatus(): Promise<ConnectionDetails> {
    console.info('[NetworkService] Checking connection status...');

    const isAccessible = this.isNetworkAccessible();

    const hasWifi = this.checkWifiConnection();
    const hasCellular = await this.checkCellularConnection();
    const hasBluetooth = this.checkBluetoothConnection();

    const hasAnyConnection = hasWifi || hasCellular || hasBluetooth;

    const connectionType = this.getActiveConnectionType();

    let status: ConnectionStatus;
    let message: string;

    if (isAccessible && hasAnyConnection) {
      status = ConnectionStatus.CONNECTED;
      message = `There is no internet connection (${connectionType})`;
    } else if (hasAnyConnection && !isAccessible) {
      status = ConnectionStatus.DISCONNECTED;
      message = 'There is a connection but not accesible';
    } else {
      status = ConnectionStatus.DISCONNECTED;
      message = 'There is no connection';
    }

    const details: ConnectionDetails = {
      status,
      isNetworkAccessible: isAccessible,
      hasWifi,
      hasCellular,
      hasBluetooth,
      connectionType,
      message
    };

    console.info('[NetworkService] Status:', JSON.stringify(details));

    this.notifyConnectionStatusChanged(details);

    return details;
  }


  public addConnectionStatusListener(callback: (details: ConnectionDetails) => void): void {
    this.connectionStatusCallbacks.push(callback);
  }


  public removeConnectionStatusListener(callback: (details: ConnectionDetails) => void): void {
    const index = this.connectionStatusCallbacks.indexOf(callback);
    if (index > -1) {
      this.connectionStatusCallbacks.splice(index, 1);
    }
  }


  private notifyConnectionStatusChanged(details: ConnectionDetails): void {
    this.connectionStatusCallbacks.forEach(callback => {
      try {
        callback(details);
      } catch (error) {
        console.error('[NetworkService] Callback error:', JSON.stringify(error));
      }
    });
  }


  public async canMakeNetworkRequest(): Promise<boolean> {
    const details = await this.checkConnectionStatus();
    return details.status === ConnectionStatus.CONNECTED && details.isNetworkAccessible;
  }


  public async destroy(): Promise<void> {
    if (this.netConnection) {
      try {
        this.netConnection.unregister((error: BusinessError) => {
          if (error) {
            console.error('[NetworkService] Unregister error:', JSON.stringify(error));
          } else {
            console.info('[NetworkService] Unregistered successfully');
          }
        });
      } catch (error) {
        console.error('[NetworkService] Unregister exception:', JSON.stringify(error));
      }
      this.netConnection = undefined;
    }

    this.connectionStatusCallbacks = [];
    this.isInitialized = false;
    console.info('[NetworkService] Destroyed');
  }
}
