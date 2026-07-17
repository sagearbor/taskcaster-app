import '../../../telephone/data/datasources/nearby_telephone_transport.dart';
import 'clue_hunt_transport.dart';

/// App-unique Nearby service id for Clue Hunt. Distinct from the Telephone and
/// Balloon Blitz ids so the offline games never discover each other, but
/// identical on a Clue Hunt host and every seeker so a family only finds *their*
/// hunt.
const String kClueHuntNearbyServiceId =
    'com.sagearbor.taskcaster.cluehunt';

/// The real offline transport: the exact framed Google Nearby Connections bus
/// the Telephone/Blitz games use (Bluetooth + Wi-Fi Direct, no internet),
/// pointed at the Clue Hunt service id. Subclassing reuses all of the chunking,
/// reassembly, discovery and auto-accept handshake code unchanged.
///
/// DEVICE-ONLY: the underlying radio work runs only on physical Android phones;
/// off-device every method short-circuits (see [NearbyTelephoneTransport]).
class NearbyClueHuntTransport extends NearbyTelephoneTransport
    implements ClueHuntTransport {
  NearbyClueHuntTransport() : super(serviceId: kClueHuntNearbyServiceId);
}
