import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'network_event.dart';
import 'network_logger.dart';
import 'network_logger_screen.dart';

/// Overlay for [NetworkLoggerButton].
class NetworkLoggerOverlay extends StatefulWidget {
  static const double _defaultPadding = 30;

  const NetworkLoggerOverlay._({
    required this.right,
    required this.bottom,
    required this.draggable,
    Key? key,
  }) : super(key: key);

  final double bottom;
  final double right;
  final bool draggable;

  /// Attach overlay to specified [context]. The FAB will be draggable unless
  /// [draggable] set to `false`. Initial distance from the button to the screen
  /// edge can be configured using [bottom] and [right] parameters.
  static OverlayEntry attachTo(
    BuildContext context, {
    bool rootOverlay = true,
    double bottom = _defaultPadding,
    double right = _defaultPadding,
    bool draggable = true,
  }) {
    // create overlay entry
    final entry = OverlayEntry(
      builder: (context) => NetworkLoggerOverlay._(
        bottom: bottom,
        right: right,
        draggable: draggable,
      ),
    );
    // insert on next frame
    Future.delayed(Duration.zero, () {
      final overlay = Overlay.maybeOf(
        context,
        rootOverlay: rootOverlay,
      );

      if (overlay == null) {
        throw FlutterError('FlutterNetworkLogger:  No Overlay widget found.');
      }

      overlay.insert(entry);
    });
    // return
    return entry;
  }

  @override
  State<NetworkLoggerOverlay> createState() => _NetworkLoggerOverlayState();
}

class _NetworkLoggerOverlayState extends State<NetworkLoggerOverlay> {
  static const Size buttonSize = Size(57, 57);
  late double bottom = widget.bottom;
  late double right = widget.right;
  late MediaQueryData screen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    screen = MediaQuery.of(context);
  }

  Offset? lastPosition;

  void onPanUpdate(LongPressMoveUpdateDetails details) {
    final delta = lastPosition! - details.localPosition;

    bottom += delta.dy;
    right += delta.dx;

    lastPosition = details.localPosition;

    /// Checks if the button went of screen
    if (bottom < 0) {
      bottom = 0;
    }

    if (right < 0) {
      right = 0;
    }

    if (bottom + buttonSize.height > screen.size.height) {
      bottom = screen.size.height - buttonSize.height;
    }

    if (right + buttonSize.width > screen.size.width) {
      right = screen.size.width - buttonSize.width;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.draggable
      ? Positioned(
          right: right,
          bottom: bottom,
          child: GestureDetector(
            onLongPressMoveUpdate: onPanUpdate,
            onLongPressUp: () {
              setState(() => lastPosition = null);
            },
            onLongPressDown: (details) {
              setState(() => lastPosition = details.localPosition);
            },
            child: Material(
              elevation: lastPosition == null ? 0 : 30,
              borderRadius: BorderRadius.circular(buttonSize.width),
              child: NetworkLoggerButton(),
            ),
          ),
        )
      : Positioned(
          right: widget.right + screen.padding.right,
          bottom: widget.bottom + screen.padding.bottom,
          child: NetworkLoggerButton(),
        );
}

/// [FloatingActionButton] that opens [NetworkLoggerScreen] when pressed.
class NetworkLoggerButton extends StatefulWidget {
  /// Source event list (default: [NetworkLogger.instance])
  final NetworkEventList eventList;

  /// Blink animation period
  final Duration blinkPeriod;

  // Button background color
  final Color color;

  /// If set to true this button will be hidden on non-debug builds.
  final bool showOnlyOnDebug;

  NetworkLoggerButton({
    Key? key,
    this.color = Colors.deepPurple,
    this.blinkPeriod = const Duration(seconds: 1, microseconds: 500),
    this.showOnlyOnDebug = false,
    NetworkEventList? eventList,
  })  : eventList = eventList ?? NetworkLogger.instance,
        super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _NetworkLoggerButtonState createState() => _NetworkLoggerButtonState();
}

class _NetworkLoggerButtonState extends State<NetworkLoggerButton> {
  StreamSubscription<dynamic>? _subscription;
  Timer? _blinkTimer;
  bool _visible = true;
  int _blink = 0;

  Future<void> _press() async {
    setState(() {
      _visible = false;
    });
    try {
      await NetworkLoggerScreen.open(
        context,
        eventList: widget.eventList,
      );
    } finally {
      if (mounted) {
        setState(() {
          _visible = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant NetworkLoggerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventList != widget.eventList) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.eventList.stream.listen((event) {
      if (mounted) {
        setState(() {
          _blink = _blink % 2 == 0 ? 6 : 5;
        });
      }
    });
  }

  @override
  void initState() {
    _subscribe();
    _blinkTimer = Timer.periodic(widget.blinkPeriod, (timer) {
      if (_blink > 0 && mounted) {
        setState(() {
          _blink--;
        });
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_visible
      ? const SizedBox()
      : FloatingActionButton(
          onPressed: _press,
          shape: const CircleBorder(),
          backgroundColor: widget.color,
          child: Icon(
            (_blink % 2 == 0) ? Icons.cloud : Icons.cloud_queue,
            color: Colors.white,
          ),
        );
}

/// Screen that displays log entries list.

const _jsonEncoder = JsonEncoder.withIndent('  ');

/// Screen that displays log entry details.
class NetworkLoggerEventScreen extends StatelessWidget {
  /// Which event to display details for.
  final NetworkEvent event;

  const NetworkLoggerEventScreen({
    Key? key,
    required this.event,
  }) : super(key: key);

  static Route<void> route({
    required NetworkEvent event,
    required NetworkEventList eventList,
  }) =>
      MaterialPageRoute(
        builder: (context) => StreamBuilder(
          stream: eventList.stream.where((item) => item.event == event),
          builder: (context, snapshot) => NetworkLoggerEventScreen(event: event),
        ),
      );

  /// Opens screen.
  static Future<void> open(
    BuildContext context,
    NetworkEvent event,
    NetworkEventList eventList,
  ) =>
      Navigator.of(context).push(route(
        event: event,
        eventList: eventList,
      ));

  @override
  Widget build(BuildContext context) {
    final showResponse = event.response != null;

    Widget? bottom;
    if (showResponse) {
      bottom = const TabBar(
        tabs: [
          Tab(text: 'Request'),
          Tab(text: 'Response'),
        ],
      );
    }

    return DefaultTabController(
      initialIndex: 0,
      length: showResponse ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Network Log'),
          bottom: (bottom as PreferredSizeWidget?),
          actions: [
            InkWell(
              onTap: () => copyCurl(
                context,
                event,
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('CURL'),
              ),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => TabBarView(
            children: <Widget>[
              buildRequestView(context),
              if (showResponse) buildResponseView(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildBodyViewer(BuildContext context, dynamic body) {
    String text;
    if (body == null) {
      text = '';
    } else if (body is String) {
      text = body;
    } else if (body is List || body is Map) {
      text = _jsonEncoder.convert(body);
    } else {
      text = body.toString();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied to clipboard'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['sans-serif'],
          ),
        ),
      ),
    );
  }

  Widget buildHeadersViewer(
    BuildContext context,
    List<MapEntry<String, String>> headers,
  ) =>
      Column(
        children: [
          ...headers
              .map(
                (e) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text('${e.key}: '),
                    ),
                    Flexible(
                      child: Text(e.value),
                    ),
                  ],
                ),
              )
              .toList(),
        ],
      );

  Widget buildRequestView(BuildContext context) => ListView(
        padding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 15,
        ),
        children: <Widget>[
          Text(
            'URL',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.request!.method,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: SelectableText(event.request!.uri.toString()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'TIMESTAMP',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(event.timestamp.toString()),
          const SizedBox(height: 16),
          if (event.request!.headers.isNotEmpty) ...[
            Text(
              'HEADERS',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            buildHeadersViewer(
              context,
              event.request!.headers.entries,
            ),
          ],
          if (event.error != null) ...[
            Text(
              'ERROR',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              event.error.toString(),
              style: const TextStyle(color: Colors.red),
            ),
          ],
          Text(
            'BODY',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          buildBodyViewer(
            context,
            jsonDecode(jsonEncode(event.request!.data)),
          ),
        ],
      );

  Widget buildResponseView(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('RESULT', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.response!.statusCode.toString(),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(width: 15),
              Expanded(child: Text(event.response!.statusMessage)),
            ],
          ),
          if (event.response?.headers.isNotEmpty ?? false) ...[
            Text('HEADERS', style: Theme.of(context).textTheme.bodySmall),
            buildHeadersViewer(
              context,
              event.response?.headers.entries ?? [],
            ),
          ],
          Text('BODY', style: Theme.of(context).textTheme.bodySmall),
          buildBodyViewer(
            context,
            event.response?.data,
          ),
        ],
      );
}

void copyCurl(
  BuildContext context,
  NetworkEvent event,
) {
  List<String> components = ['\$ curl -i'];

  if (event.request!.method.toUpperCase() == 'GET') {
    components.add('-X ${event.request!.method}');
  }

  for (final element in event.request!.headers.entries) {
    if (element.key != 'Cookie') {
      components.add('-H \'${element.key}: ${element.value}\'');
    }
  }

  var data = jsonEncode(event.request!.data);
  data = data.replaceAll(
    '\'',
    '\\\'',
  );
  components.add('-d \'$data\'');

  components.add('\'${event.request!.uri.toString()}\'');

  String curl = components.join('\\\n\t');

  Clipboard.setData(
    ClipboardData(text: curl),
  ).then(
    (value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('copied'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    },
  );
}
