import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The conversation's pages (`prototype/js/screens/chat_pages.js`) on the
/// sample data.

HelixPersonItem _p(String id) => OrbitFakes.people[id]!;

final _targets = [
  for (final c in OrbitFakes.chats)
    ForwardTargetItem(id: c.id, title: c.title, avatar: c.avatar),
];

MessageInfoModel _info({required bool group}) => MessageInfoModel(
  message: HelixMessage(
    id: 'x',
    outgoing: true,
    content: HelixTextContent(
      group
          ? 'Me too, landing Thursday night ✈️'
          : 'Here it is. The colour pages are 14 to 22',
    ),
    timeLabel: group ? '18:40' : '21:09',
    status: HelixDeliveryStatus.read,
  ),
  sentLabel: group ? 'Sunday, 18:40' : 'Yesterday, 21:09',
  isGroup: group,
  recipients: [
    for (final (id, s)
        in group
            ? const [
                ('ammu', 'Read Sunday, 18:41'),
                ('abbu', 'Read Sunday, 18:52'),
                ('rumana', 'Delivered Sunday, 18:40'),
                ('karim', 'Not delivered yet'),
              ]
            : const [('nadia', 'Read yesterday, 21:12')])
      ReceiptItem(
        name: _p(id).names.display,
        avatar: _p(id).avatar,
        readLabel: s.startsWith('Read') ? s : null,
        deliveredLabel: s.startsWith('Delivered') ? s : null,
      ),
  ],
);

/// `ITEMS` in the prototype: six pictures, the third a video.
const _items = [
  ViewerItem(swatch: 'ph-e'),
  ViewerItem(swatch: 'ph-c'),
  ViewerItem(swatch: 'ph-b', isVideo: true),
  ViewerItem(swatch: 'ph-d'),
  ViewerItem(swatch: 'ph-a'),
  ViewerItem(swatch: 'ph-f'),
];

MediaViewerModel _viewer({
  int i = 0,
  ViewerState state = ViewerState.ready,
  VideoView video = const VideoView(durationLabel: '0:24'),
}) => MediaViewerModel(
  state: state,
  title: state == ViewerState.viewOnceMine ? 'View once' : 'Nadia Rahman',
  timeLabel: 'Today, 09:40',
  caption: 'Sunset at Inani beach 🌅',
  items: _items,
  initialIndex: i,
  canShare:
      state != ViewerState.viewOnceOpened &&
      state != ViewerState.viewOnceMine &&
      state != ViewerState.nothingToShow,
  video: video,
);

/// The media tab's tiles: `['ph-e', 'ph-c', 'ph-b', …]`, the 3rd and 8th
/// videos.
final _media = [
  for (final (i, s) in const [
    'ph-e',
    'ph-c',
    'ph-b',
    'ph-d',
    'ph-a',
    'ph-f',
    'ph-c',
    'ph-e',
    'ph-d',
  ].indexed)
    SharedTileItem(swatch: s, isVideo: i == 2 || i == 7, durationLabel: '0:24'),
];

SharedMediaModel _shared(SharedTab tab, {bool empty = false}) =>
    SharedMediaModel(
      title: empty ? 'Arif Hossain' : 'Nadia Rahman',
      initialTab: tab,
      media: empty ? const [] : _media,
      documents: empty
          ? const []
          : const [
              SharedDocItem(
                name: 'Launch deck v3.pdf',
                detail: '4.2 MB · PDF · Yesterday',
              ),
              SharedDocItem(
                name: 'Venue floor plan.png',
                detail: '880 KB · PNG · 3 Oct',
              ),
            ],
      links: empty
          ? const []
          : const [
              SharedLinkItem(
                url: 'https://helix.agiletechbd.com/blog/v2',
                detail: 'helix.agiletechbd.com, today',
              ),
              SharedLinkItem(
                url: 'https://maps.google.com/?q=Inani+Beach',
                detail: 'maps.google.com, yesterday',
              ),
            ],
    );

ChatSettingsModel _settings(String id) {
  final group = id.startsWith('group:');
  final chat = OrbitFakes.chats.where((c) => c.id == id).firstOrNull;
  final p = group ? null : _p(id.split(':')[1]);
  return ChatSettingsModel(
    title: group ? chat!.title : p!.names.display,
    subtitle: group
        ? '5 members'
        : p!.online
        ? 'online'
        : p.names.secondary ?? '',
    avatar: group ? chat!.avatar : p!.avatar,
    isGroup: group,
    disappearingLabel: group ? '1 week' : 'Off',
    disappearingSeconds: group ? 604800 : null,
    blocked: p?.blocked ?? false,
  );
}

/// The send-files page keeps the list itself, so × works in the preview.
class _PreviewSendFiles extends StatefulWidget {
  const _PreviewSendFiles({this.empty = false});

  final bool empty;

  @override
  State<_PreviewSendFiles> createState() => _PreviewSendFilesState();
}

class _PreviewSendFilesState extends State<_PreviewSendFiles> {
  late final _files = widget.empty
      ? <SendFileItem>[]
      : [
          const SendFileItem(
            id: '1',
            name: 'IMG_2041.jpg',
            sizeLabel: '2.4 MB',
            kind: SendFileKind.image,
            swatch: 'ph-e',
          ),
          const SendFileItem(
            id: '2',
            name: 'VID_0310.mp4',
            sizeLabel: '18.1 MB',
            kind: SendFileKind.video,
            swatch: 'ph-b',
          ),
          const SendFileItem(
            id: '3',
            name: 'Invoice October.pdf',
            sizeLabel: '312 KB',
            kind: SendFileKind.document,
          ),
        ];

  @override
  Widget build(BuildContext context) => SendFilesScreen(
    model: SendFilesModel(files: _files),
    actions: SendFilesActions(
      onRemove: (id) => setState(() => _files.removeWhere((f) => f.id == id)),
    ),
  );
}

final Map<String, WidgetBuilder> chatPagePreviews = {
  'forward': (_) =>
      ForwardScreen(model: ForwardModel(messageCount: 1, targets: _targets)),
  'forward-picked': (_) => ForwardScreen(
    model: ForwardModel(messageCount: 2, targets: _targets),
    initialPicked: const {'group:family', 'direct:arif'},
  ),
  'message-info': (_) => MessageInfoScreen(model: _info(group: false)),
  'message-info-group': (_) => MessageInfoScreen(model: _info(group: true)),
  'message-info-gone': (_) => const MessageInfoScreen(
    model: MessageInfoModel(loadState: MessageInfoState.notFound),
  ),
  'media-viewer': (_) => MediaViewerScreen(model: _viewer()),
  'media-video': (_) => MediaViewerScreen(model: _viewer(i: 2)),
  'media-video-failed': (_) => MediaViewerScreen(
    model: _viewer(i: 2, video: const VideoView(phase: VideoPhase.failed)),
  ),
  'media-not-here': (_) =>
      MediaViewerScreen(model: _viewer(state: ViewerState.nothingToShow)),
  'media-cannot-show': (_) =>
      MediaViewerScreen(model: _viewer(state: ViewerState.cannotShow)),
  'media-video-buffering': (_) => MediaViewerScreen(
    model: _viewer(i: 2, video: const VideoView(buffering: true)),
  ),
  'media-video-ended': (_) => MediaViewerScreen(
    model: _viewer(i: 2, video: const VideoView(completed: true)),
  ),
  'media-viewonce-opened': (_) =>
      MediaViewerScreen(model: _viewer(state: ViewerState.viewOnceOpened)),
  'media-viewonce-mine': (_) =>
      MediaViewerScreen(model: _viewer(state: ViewerState.viewOnceMine)),
  'send-files': (_) => const _PreviewSendFiles(),
  'send-files-empty': (_) => const _PreviewSendFiles(empty: true),
  'shared': (_) => SharedMediaScreen(model: _shared(SharedTab.media)),
  'shared-docs': (_) => SharedMediaScreen(model: _shared(SharedTab.docs)),
  'shared-links': (_) => SharedMediaScreen(model: _shared(SharedTab.links)),
  'shared-empty': (_) =>
      SharedMediaScreen(model: _shared(SharedTab.media, empty: true)),
  'shared-docs-empty': (_) =>
      SharedMediaScreen(model: _shared(SharedTab.docs, empty: true)),
  'shared-links-empty': (_) =>
      SharedMediaScreen(model: _shared(SharedTab.links, empty: true)),
  'chat-settings': (_) => ChatSettingsScreen(model: _settings('direct:nadia')),
  'chat-settings-group': (_) =>
      ChatSettingsScreen(model: _settings('group:family')),
  'chat-settings-blocked': (_) =>
      ChatSettingsScreen(model: _settings('direct:shuvo')),
};
