import 'dart:async';

import 'package:flutter/material.dart';

import 'enumerate_items.dart';
import 'network_event.dart';
import 'network_logger.dart';
import 'ui.dart';

class NetworkLoggerScreen extends StatelessWidget {
  NetworkLoggerScreen({
    Key? key,
    NetworkEventList? eventList,
  })  : eventList = eventList ?? NetworkLogger.instance,
        super(key: key);

  /// Event list to listen for event changes.
  final NetworkEventList eventList;

  /// Opens screen.
  static Future<void> open(
    BuildContext context, {
    NetworkEventList? eventList,
  }) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NetworkLoggerScreen(eventList: eventList),
        ),
      );

  final TextEditingController searchController = TextEditingController(text: null);

  /// filte events with search keyword
  List<NetworkEvent> getEvents() {
    if (searchController.text.isEmpty) return eventList.events;

    final query = searchController.text.toLowerCase();
    return eventList.events.where((it) => it.request?.uri.toLowerCase().contains(query) ?? false).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Network Logs'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => eventList.clear(),
            ),
          ],
        ),
        body: StreamBuilder(
          stream: eventList.stream,
          builder: (context, snapshot) {
            // filter events with search keyword
            final events = getEvents();

            return Column(
              children: [
                TextField(
                  controller: searchController,
                  onChanged: (text) {
                    eventList.updated(NetworkEvent());
                  },
                  autocorrect: false,
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search, color: Colors.black26),
                    suffix: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: searchController,
                      builder: (context, value, child) =>
                          value.text.isNotEmpty ? Text('${getEvents().length} results') : const SizedBox(),
                    ),
                    hintText: 'Search',
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: events.length,
                    itemBuilder: enumerateItems<NetworkEvent>(
                      events,
                      (context, item) => ListTile(
                        key: ValueKey(item.request),
                        title: Text(
                          item.request!.method,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          item.request!.uri.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        leading: Icon(
                          item.error == null
                              ? (item.response == null ? Icons.hourglass_empty : Icons.done)
                              : Icons.error,
                        ),
                        trailing: _AutoUpdate(
                          duration: const Duration(seconds: 1),
                          builder: (context) => Text(_timeDifference(item.timestamp!)),
                        ),
                        onTap: () => NetworkLoggerEventScreen.open(
                          context,
                          item,
                          eventList,
                        ),
                      ),
                    ),
                  ),
                )
              ],
            );
          },
        ),
      );
}

/// Widget builder that re-builds widget repeatedly with [duration] interval.
class _AutoUpdate extends StatefulWidget {
  const _AutoUpdate({Key? key, required this.duration, required this.builder}) : super(key: key);

  /// Re-build interval.
  final Duration duration;

  /// Widget builder to build widget.
  final WidgetBuilder builder;

  @override
  _AutoUpdateState createState() => _AutoUpdateState();
}

class _AutoUpdateState extends State<_AutoUpdate> {
  Timer? _timer;

  void _setTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.duration, (timer) {
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(_AutoUpdate old) {
    if (old.duration != widget.duration) {
      _setTimer();
    }
    super.didUpdateWidget(old);
  }

  @override
  void initState() {
    _setTimer();
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

String _timeDifference(DateTime time, [DateTime? origin]) {
  origin ??= DateTime.now();
  var delta = origin.difference(time);
  if (delta.inSeconds < 90) {
    return '${delta.inSeconds} s';
  } else if (delta.inMinutes < 90) {
    return '${delta.inMinutes} m';
  } else {
    return '${delta.inHours} h';
  }
}
