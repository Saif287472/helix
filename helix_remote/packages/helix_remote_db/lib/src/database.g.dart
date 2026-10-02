// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class MessagesFts extends Table
    with
        TableInfo<MessagesFts, MessagesFt>,
        VirtualTableInfo<MessagesFts, MessagesFt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MessagesFts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages_fts';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessagesFt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  MessagesFt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessagesFt(
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  MessagesFts createAlias(String alias) {
    return MessagesFts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(body, content = \'messages\', content_rowid = \'local_rowid\', tokenize = \'unicode61 remove_diacritics 2 categories \'\'L* N* Co M*\'\'\')';
}

class MessagesFt extends DataClass implements Insertable<MessagesFt> {
  final String body;
  const MessagesFt({required this.body});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['body'] = Variable<String>(body);
    return map;
  }

  MessagesFtsCompanion toCompanion(bool nullToAbsent) {
    return MessagesFtsCompanion(body: Value(body));
  }

  factory MessagesFt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessagesFt(body: serializer.fromJson<String>(json['body']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'body': serializer.toJson<String>(body)};
  }

  MessagesFt copyWith({String? body}) => MessagesFt(body: body ?? this.body);
  MessagesFt copyWithCompanion(MessagesFtsCompanion data) {
    return MessagesFt(body: data.body.present ? data.body.value : this.body);
  }

  @override
  String toString() {
    return (StringBuffer('MessagesFt(')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => body.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessagesFt && other.body == this.body);
}

class MessagesFtsCompanion extends UpdateCompanion<MessagesFt> {
  final Value<String> body;
  final Value<int> rowid;
  const MessagesFtsCompanion({
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesFtsCompanion.insert({
    required String body,
    this.rowid = const Value.absent(),
  }) : body = Value(body);
  static Insertable<MessagesFt> custom({
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesFtsCompanion copyWith({Value<String>? body, Value<int>? rowid}) {
    return MessagesFtsCompanion(
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesFtsCompanion(')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, ConversationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ConversationKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ConversationKind>($ConversationsTable.$converterkind);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<Uint8List> avatar = GeneratedColumn<Uint8List>(
    'avatar',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> pinnedAt =
      GeneratedColumn<int>(
        'pinned_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($ConversationsTable.$converterpinnedAtn);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> mutedUntil =
      GeneratedColumn<int>(
        'muted_until',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($ConversationsTable.$convertermutedUntiln);
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastMessageRowidMeta = const VerificationMeta(
    'lastMessageRowid',
  );
  @override
  late final GeneratedColumn<int> lastMessageRowid = GeneratedColumn<int>(
    'last_message_rowid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageSortKeyMeta =
      const VerificationMeta('lastMessageSortKey');
  @override
  late final GeneratedColumn<String> lastMessageSortKey =
      GeneratedColumn<String>(
        'last_message_sort_key',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastMessageAt =
      GeneratedColumn<int>(
        'last_message_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($ConversationsTable.$converterlastMessageAtn);
  static const VerificationMeta _lastMessagePreviewMeta =
      const VerificationMeta('lastMessagePreview');
  @override
  late final GeneratedColumn<String> lastMessagePreview =
      GeneratedColumn<String>(
        'last_message_preview',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mentionCountMeta = const VerificationMeta(
    'mentionCount',
  );
  @override
  late final GeneratedColumn<int> mentionCount = GeneratedColumn<int>(
    'mention_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastReadSortKeyMeta = const VerificationMeta(
    'lastReadSortKey',
  );
  @override
  late final GeneratedColumn<String> lastReadSortKey = GeneratedColumn<String>(
    'last_read_sort_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _draftMeta = const VerificationMeta('draft');
  @override
  late final GeneratedColumn<String> draft = GeneratedColumn<String>(
    'draft',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _disappearingSecondsMeta =
      const VerificationMeta('disappearingSeconds');
  @override
  late final GeneratedColumn<int> disappearingSeconds = GeneratedColumn<int>(
    'disappearing_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($ConversationsTable.$convertercreatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    title,
    avatar,
    pinnedAt,
    mutedUntil,
    archived,
    lastMessageRowid,
    lastMessageSortKey,
    lastMessageAt,
    lastMessagePreview,
    unreadCount,
    mentionCount,
    lastReadSortKey,
    draft,
    disappearingSeconds,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('last_message_rowid')) {
      context.handle(
        _lastMessageRowidMeta,
        lastMessageRowid.isAcceptableOrUnknown(
          data['last_message_rowid']!,
          _lastMessageRowidMeta,
        ),
      );
    }
    if (data.containsKey('last_message_sort_key')) {
      context.handle(
        _lastMessageSortKeyMeta,
        lastMessageSortKey.isAcceptableOrUnknown(
          data['last_message_sort_key']!,
          _lastMessageSortKeyMeta,
        ),
      );
    }
    if (data.containsKey('last_message_preview')) {
      context.handle(
        _lastMessagePreviewMeta,
        lastMessagePreview.isAcceptableOrUnknown(
          data['last_message_preview']!,
          _lastMessagePreviewMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('mention_count')) {
      context.handle(
        _mentionCountMeta,
        mentionCount.isAcceptableOrUnknown(
          data['mention_count']!,
          _mentionCountMeta,
        ),
      );
    }
    if (data.containsKey('last_read_sort_key')) {
      context.handle(
        _lastReadSortKeyMeta,
        lastReadSortKey.isAcceptableOrUnknown(
          data['last_read_sort_key']!,
          _lastReadSortKeyMeta,
        ),
      );
    }
    if (data.containsKey('draft')) {
      context.handle(
        _draftMeta,
        draft.isAcceptableOrUnknown(data['draft']!, _draftMeta),
      );
    }
    if (data.containsKey('disappearing_seconds')) {
      context.handle(
        _disappearingSecondsMeta,
        disappearingSeconds.isAcceptableOrUnknown(
          data['disappearing_seconds']!,
          _disappearingSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: $ConversationsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}avatar'],
      ),
      pinnedAt: $ConversationsTable.$converterpinnedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}pinned_at'],
        ),
      ),
      mutedUntil: $ConversationsTable.$convertermutedUntiln.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}muted_until'],
        ),
      ),
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      lastMessageRowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_message_rowid'],
      ),
      lastMessageSortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_sort_key'],
      ),
      lastMessageAt: $ConversationsTable.$converterlastMessageAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_message_at'],
        ),
      ),
      lastMessagePreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_preview'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      mentionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mention_count'],
      )!,
      lastReadSortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_read_sort_key'],
      ),
      draft: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft'],
      ),
      disappearingSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disappearing_seconds'],
      ),
      createdAt: $ConversationsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ConversationKind, String, String> $converterkind =
      const EnumNameConverter<ConversationKind>(ConversationKind.values);
  static TypeConverter<DateTime, int> $converterpinnedAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterpinnedAtn =
      NullAwareTypeConverter.wrap($converterpinnedAt);
  static TypeConverter<DateTime, int> $convertermutedUntil = const EpochMs();
  static TypeConverter<DateTime?, int?> $convertermutedUntiln =
      NullAwareTypeConverter.wrap($convertermutedUntil);
  static TypeConverter<DateTime, int> $converterlastMessageAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterlastMessageAtn =
      NullAwareTypeConverter.wrap($converterlastMessageAt);
  static TypeConverter<DateTime, int> $convertercreatedAt = const EpochMs();
}

class ConversationRow extends DataClass implements Insertable<ConversationRow> {
  /// `direct:<peer account>` for direct chats ([directConversationId]).
  final String id;
  final ConversationKind kind;
  final String? title;
  final Uint8List? avatar;
  final DateTime? pinnedAt;
  final DateTime? mutedUntil;
  final bool archived;

  /// `messages.local_rowid` of the newest message (by sort key).
  final int? lastMessageRowid;
  final String? lastMessageSortKey;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadCount;
  final int mentionCount;

  /// The user has read everything up to this sort key.
  final String? lastReadSortKey;
  final String? draft;
  final int? disappearingSeconds;
  final DateTime createdAt;
  const ConversationRow({
    required this.id,
    required this.kind,
    this.title,
    this.avatar,
    this.pinnedAt,
    this.mutedUntil,
    required this.archived,
    this.lastMessageRowid,
    this.lastMessageSortKey,
    this.lastMessageAt,
    this.lastMessagePreview,
    required this.unreadCount,
    required this.mentionCount,
    this.lastReadSortKey,
    this.draft,
    this.disappearingSeconds,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['kind'] = Variable<String>(
        $ConversationsTable.$converterkind.toSql(kind),
      );
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || avatar != null) {
      map['avatar'] = Variable<Uint8List>(avatar);
    }
    if (!nullToAbsent || pinnedAt != null) {
      map['pinned_at'] = Variable<int>(
        $ConversationsTable.$converterpinnedAtn.toSql(pinnedAt),
      );
    }
    if (!nullToAbsent || mutedUntil != null) {
      map['muted_until'] = Variable<int>(
        $ConversationsTable.$convertermutedUntiln.toSql(mutedUntil),
      );
    }
    map['archived'] = Variable<bool>(archived);
    if (!nullToAbsent || lastMessageRowid != null) {
      map['last_message_rowid'] = Variable<int>(lastMessageRowid);
    }
    if (!nullToAbsent || lastMessageSortKey != null) {
      map['last_message_sort_key'] = Variable<String>(lastMessageSortKey);
    }
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<int>(
        $ConversationsTable.$converterlastMessageAtn.toSql(lastMessageAt),
      );
    }
    if (!nullToAbsent || lastMessagePreview != null) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['mention_count'] = Variable<int>(mentionCount);
    if (!nullToAbsent || lastReadSortKey != null) {
      map['last_read_sort_key'] = Variable<String>(lastReadSortKey);
    }
    if (!nullToAbsent || draft != null) {
      map['draft'] = Variable<String>(draft);
    }
    if (!nullToAbsent || disappearingSeconds != null) {
      map['disappearing_seconds'] = Variable<int>(disappearingSeconds);
    }
    {
      map['created_at'] = Variable<int>(
        $ConversationsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      kind: Value(kind),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      avatar: avatar == null && nullToAbsent
          ? const Value.absent()
          : Value(avatar),
      pinnedAt: pinnedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pinnedAt),
      mutedUntil: mutedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(mutedUntil),
      archived: Value(archived),
      lastMessageRowid: lastMessageRowid == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageRowid),
      lastMessageSortKey: lastMessageSortKey == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageSortKey),
      lastMessageAt: lastMessageAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageAt),
      lastMessagePreview: lastMessagePreview == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessagePreview),
      unreadCount: Value(unreadCount),
      mentionCount: Value(mentionCount),
      lastReadSortKey: lastReadSortKey == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadSortKey),
      draft: draft == null && nullToAbsent
          ? const Value.absent()
          : Value(draft),
      disappearingSeconds: disappearingSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(disappearingSeconds),
      createdAt: Value(createdAt),
    );
  }

  factory ConversationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationRow(
      id: serializer.fromJson<String>(json['id']),
      kind: $ConversationsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      title: serializer.fromJson<String?>(json['title']),
      avatar: serializer.fromJson<Uint8List?>(json['avatar']),
      pinnedAt: serializer.fromJson<DateTime?>(json['pinnedAt']),
      mutedUntil: serializer.fromJson<DateTime?>(json['mutedUntil']),
      archived: serializer.fromJson<bool>(json['archived']),
      lastMessageRowid: serializer.fromJson<int?>(json['lastMessageRowid']),
      lastMessageSortKey: serializer.fromJson<String?>(
        json['lastMessageSortKey'],
      ),
      lastMessageAt: serializer.fromJson<DateTime?>(json['lastMessageAt']),
      lastMessagePreview: serializer.fromJson<String?>(
        json['lastMessagePreview'],
      ),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      mentionCount: serializer.fromJson<int>(json['mentionCount']),
      lastReadSortKey: serializer.fromJson<String?>(json['lastReadSortKey']),
      draft: serializer.fromJson<String?>(json['draft']),
      disappearingSeconds: serializer.fromJson<int?>(
        json['disappearingSeconds'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(
        $ConversationsTable.$converterkind.toJson(kind),
      ),
      'title': serializer.toJson<String?>(title),
      'avatar': serializer.toJson<Uint8List?>(avatar),
      'pinnedAt': serializer.toJson<DateTime?>(pinnedAt),
      'mutedUntil': serializer.toJson<DateTime?>(mutedUntil),
      'archived': serializer.toJson<bool>(archived),
      'lastMessageRowid': serializer.toJson<int?>(lastMessageRowid),
      'lastMessageSortKey': serializer.toJson<String?>(lastMessageSortKey),
      'lastMessageAt': serializer.toJson<DateTime?>(lastMessageAt),
      'lastMessagePreview': serializer.toJson<String?>(lastMessagePreview),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'mentionCount': serializer.toJson<int>(mentionCount),
      'lastReadSortKey': serializer.toJson<String?>(lastReadSortKey),
      'draft': serializer.toJson<String?>(draft),
      'disappearingSeconds': serializer.toJson<int?>(disappearingSeconds),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ConversationRow copyWith({
    String? id,
    ConversationKind? kind,
    Value<String?> title = const Value.absent(),
    Value<Uint8List?> avatar = const Value.absent(),
    Value<DateTime?> pinnedAt = const Value.absent(),
    Value<DateTime?> mutedUntil = const Value.absent(),
    bool? archived,
    Value<int?> lastMessageRowid = const Value.absent(),
    Value<String?> lastMessageSortKey = const Value.absent(),
    Value<DateTime?> lastMessageAt = const Value.absent(),
    Value<String?> lastMessagePreview = const Value.absent(),
    int? unreadCount,
    int? mentionCount,
    Value<String?> lastReadSortKey = const Value.absent(),
    Value<String?> draft = const Value.absent(),
    Value<int?> disappearingSeconds = const Value.absent(),
    DateTime? createdAt,
  }) => ConversationRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    title: title.present ? title.value : this.title,
    avatar: avatar.present ? avatar.value : this.avatar,
    pinnedAt: pinnedAt.present ? pinnedAt.value : this.pinnedAt,
    mutedUntil: mutedUntil.present ? mutedUntil.value : this.mutedUntil,
    archived: archived ?? this.archived,
    lastMessageRowid: lastMessageRowid.present
        ? lastMessageRowid.value
        : this.lastMessageRowid,
    lastMessageSortKey: lastMessageSortKey.present
        ? lastMessageSortKey.value
        : this.lastMessageSortKey,
    lastMessageAt: lastMessageAt.present
        ? lastMessageAt.value
        : this.lastMessageAt,
    lastMessagePreview: lastMessagePreview.present
        ? lastMessagePreview.value
        : this.lastMessagePreview,
    unreadCount: unreadCount ?? this.unreadCount,
    mentionCount: mentionCount ?? this.mentionCount,
    lastReadSortKey: lastReadSortKey.present
        ? lastReadSortKey.value
        : this.lastReadSortKey,
    draft: draft.present ? draft.value : this.draft,
    disappearingSeconds: disappearingSeconds.present
        ? disappearingSeconds.value
        : this.disappearingSeconds,
    createdAt: createdAt ?? this.createdAt,
  );
  ConversationRow copyWithCompanion(ConversationsCompanion data) {
    return ConversationRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      title: data.title.present ? data.title.value : this.title,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
      mutedUntil: data.mutedUntil.present
          ? data.mutedUntil.value
          : this.mutedUntil,
      archived: data.archived.present ? data.archived.value : this.archived,
      lastMessageRowid: data.lastMessageRowid.present
          ? data.lastMessageRowid.value
          : this.lastMessageRowid,
      lastMessageSortKey: data.lastMessageSortKey.present
          ? data.lastMessageSortKey.value
          : this.lastMessageSortKey,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      lastMessagePreview: data.lastMessagePreview.present
          ? data.lastMessagePreview.value
          : this.lastMessagePreview,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      mentionCount: data.mentionCount.present
          ? data.mentionCount.value
          : this.mentionCount,
      lastReadSortKey: data.lastReadSortKey.present
          ? data.lastReadSortKey.value
          : this.lastReadSortKey,
      draft: data.draft.present ? data.draft.value : this.draft,
      disappearingSeconds: data.disappearingSeconds.present
          ? data.disappearingSeconds.value
          : this.disappearingSeconds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('avatar: $avatar, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('mutedUntil: $mutedUntil, ')
          ..write('archived: $archived, ')
          ..write('lastMessageRowid: $lastMessageRowid, ')
          ..write('lastMessageSortKey: $lastMessageSortKey, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('mentionCount: $mentionCount, ')
          ..write('lastReadSortKey: $lastReadSortKey, ')
          ..write('draft: $draft, ')
          ..write('disappearingSeconds: $disappearingSeconds, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    title,
    $driftBlobEquality.hash(avatar),
    pinnedAt,
    mutedUntil,
    archived,
    lastMessageRowid,
    lastMessageSortKey,
    lastMessageAt,
    lastMessagePreview,
    unreadCount,
    mentionCount,
    lastReadSortKey,
    draft,
    disappearingSeconds,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.title == this.title &&
          $driftBlobEquality.equals(other.avatar, this.avatar) &&
          other.pinnedAt == this.pinnedAt &&
          other.mutedUntil == this.mutedUntil &&
          other.archived == this.archived &&
          other.lastMessageRowid == this.lastMessageRowid &&
          other.lastMessageSortKey == this.lastMessageSortKey &&
          other.lastMessageAt == this.lastMessageAt &&
          other.lastMessagePreview == this.lastMessagePreview &&
          other.unreadCount == this.unreadCount &&
          other.mentionCount == this.mentionCount &&
          other.lastReadSortKey == this.lastReadSortKey &&
          other.draft == this.draft &&
          other.disappearingSeconds == this.disappearingSeconds &&
          other.createdAt == this.createdAt);
}

class ConversationsCompanion extends UpdateCompanion<ConversationRow> {
  final Value<String> id;
  final Value<ConversationKind> kind;
  final Value<String?> title;
  final Value<Uint8List?> avatar;
  final Value<DateTime?> pinnedAt;
  final Value<DateTime?> mutedUntil;
  final Value<bool> archived;
  final Value<int?> lastMessageRowid;
  final Value<String?> lastMessageSortKey;
  final Value<DateTime?> lastMessageAt;
  final Value<String?> lastMessagePreview;
  final Value<int> unreadCount;
  final Value<int> mentionCount;
  final Value<String?> lastReadSortKey;
  final Value<String?> draft;
  final Value<int?> disappearingSeconds;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.title = const Value.absent(),
    this.avatar = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.mutedUntil = const Value.absent(),
    this.archived = const Value.absent(),
    this.lastMessageRowid = const Value.absent(),
    this.lastMessageSortKey = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.mentionCount = const Value.absent(),
    this.lastReadSortKey = const Value.absent(),
    this.draft = const Value.absent(),
    this.disappearingSeconds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    required ConversationKind kind,
    this.title = const Value.absent(),
    this.avatar = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.mutedUntil = const Value.absent(),
    this.archived = const Value.absent(),
    this.lastMessageRowid = const Value.absent(),
    this.lastMessageSortKey = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.mentionCount = const Value.absent(),
    this.lastReadSortKey = const Value.absent(),
    this.draft = const Value.absent(),
    this.disappearingSeconds = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<ConversationRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? title,
    Expression<Uint8List>? avatar,
    Expression<int>? pinnedAt,
    Expression<int>? mutedUntil,
    Expression<bool>? archived,
    Expression<int>? lastMessageRowid,
    Expression<String>? lastMessageSortKey,
    Expression<int>? lastMessageAt,
    Expression<String>? lastMessagePreview,
    Expression<int>? unreadCount,
    Expression<int>? mentionCount,
    Expression<String>? lastReadSortKey,
    Expression<String>? draft,
    Expression<int>? disappearingSeconds,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (title != null) 'title': title,
      if (avatar != null) 'avatar': avatar,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (mutedUntil != null) 'muted_until': mutedUntil,
      if (archived != null) 'archived': archived,
      if (lastMessageRowid != null) 'last_message_rowid': lastMessageRowid,
      if (lastMessageSortKey != null)
        'last_message_sort_key': lastMessageSortKey,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (lastMessagePreview != null)
        'last_message_preview': lastMessagePreview,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (mentionCount != null) 'mention_count': mentionCount,
      if (lastReadSortKey != null) 'last_read_sort_key': lastReadSortKey,
      if (draft != null) 'draft': draft,
      if (disappearingSeconds != null)
        'disappearing_seconds': disappearingSeconds,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? id,
    Value<ConversationKind>? kind,
    Value<String?>? title,
    Value<Uint8List?>? avatar,
    Value<DateTime?>? pinnedAt,
    Value<DateTime?>? mutedUntil,
    Value<bool>? archived,
    Value<int?>? lastMessageRowid,
    Value<String?>? lastMessageSortKey,
    Value<DateTime?>? lastMessageAt,
    Value<String?>? lastMessagePreview,
    Value<int>? unreadCount,
    Value<int>? mentionCount,
    Value<String?>? lastReadSortKey,
    Value<String?>? draft,
    Value<int?>? disappearingSeconds,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      avatar: avatar ?? this.avatar,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      archived: archived ?? this.archived,
      lastMessageRowid: lastMessageRowid ?? this.lastMessageRowid,
      lastMessageSortKey: lastMessageSortKey ?? this.lastMessageSortKey,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      mentionCount: mentionCount ?? this.mentionCount,
      lastReadSortKey: lastReadSortKey ?? this.lastReadSortKey,
      draft: draft ?? this.draft,
      disappearingSeconds: disappearingSeconds ?? this.disappearingSeconds,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $ConversationsTable.$converterkind.toSql(kind.value),
      );
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<Uint8List>(avatar.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<int>(
        $ConversationsTable.$converterpinnedAtn.toSql(pinnedAt.value),
      );
    }
    if (mutedUntil.present) {
      map['muted_until'] = Variable<int>(
        $ConversationsTable.$convertermutedUntiln.toSql(mutedUntil.value),
      );
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (lastMessageRowid.present) {
      map['last_message_rowid'] = Variable<int>(lastMessageRowid.value);
    }
    if (lastMessageSortKey.present) {
      map['last_message_sort_key'] = Variable<String>(lastMessageSortKey.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<int>(
        $ConversationsTable.$converterlastMessageAtn.toSql(lastMessageAt.value),
      );
    }
    if (lastMessagePreview.present) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (mentionCount.present) {
      map['mention_count'] = Variable<int>(mentionCount.value);
    }
    if (lastReadSortKey.present) {
      map['last_read_sort_key'] = Variable<String>(lastReadSortKey.value);
    }
    if (draft.present) {
      map['draft'] = Variable<String>(draft.value);
    }
    if (disappearingSeconds.present) {
      map['disappearing_seconds'] = Variable<int>(disappearingSeconds.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $ConversationsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('avatar: $avatar, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('mutedUntil: $mutedUntil, ')
          ..write('archived: $archived, ')
          ..write('lastMessageRowid: $lastMessageRowid, ')
          ..write('lastMessageSortKey: $lastMessageSortKey, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('mentionCount: $mentionCount, ')
          ..write('lastReadSortKey: $lastReadSortKey, ')
          ..write('draft: $draft, ')
          ..write('disappearingSeconds: $disappearingSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages
    with TableInfo<$MessagesTable, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localRowidMeta = const VerificationMeta(
    'localRowid',
  );
  @override
  late final GeneratedColumn<int> localRowid = GeneratedColumn<int>(
    'local_rowid',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
    'sender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderDeviceMeta = const VerificationMeta(
    'senderDevice',
  );
  @override
  late final GeneratedColumn<String> senderDevice = GeneratedColumn<String>(
    'sender_device',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outgoingMeta = const VerificationMeta(
    'outgoing',
  );
  @override
  late final GeneratedColumn<bool> outgoing = GeneratedColumn<bool>(
    'outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("outgoing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> sentAt =
      GeneratedColumn<int>(
        'sent_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($MessagesTable.$convertersentAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> receivedAt =
      GeneratedColumn<int>(
        'received_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($MessagesTable.$converterreceivedAt);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToIdMeta = const VerificationMeta(
    'replyToId',
  );
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
    'reply_to_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToAuthorMeta = const VerificationMeta(
    'replyToAuthor',
  );
  @override
  late final GeneratedColumn<String> replyToAuthor = GeneratedColumn<String>(
    'reply_to_author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _forwardedMeta = const VerificationMeta(
    'forwarded',
  );
  @override
  late final GeneratedColumn<bool> forwarded = GeneratedColumn<bool>(
    'forwarded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("forwarded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _mentionsMeMeta = const VerificationMeta(
    'mentionsMe',
  );
  @override
  late final GeneratedColumn<bool> mentionsMe = GeneratedColumn<bool>(
    'mentions_me',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("mentions_me" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<MessageStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MessageStatus>($MessagesTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> editedAt =
      GeneratedColumn<int>(
        'edited_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($MessagesTable.$convertereditedAtn);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> deletedAt =
      GeneratedColumn<int>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($MessagesTable.$converterdeletedAtn);
  static const VerificationMeta _expireSecondsMeta = const VerificationMeta(
    'expireSeconds',
  );
  @override
  late final GeneratedColumn<int> expireSeconds = GeneratedColumn<int>(
    'expire_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> expiresAt =
      GeneratedColumn<int>(
        'expires_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($MessagesTable.$converterexpiresAtn);
  @override
  late final GeneratedColumnWithTypeConverter<ViewOnceState?, String>
  viewOnceState = GeneratedColumn<String>(
    'view_once_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<ViewOnceState?>($MessagesTable.$converterviewOnceStaten);
  @override
  List<GeneratedColumn> get $columns => [
    localRowid,
    messageId,
    conversationId,
    sender,
    senderDevice,
    outgoing,
    sortKey,
    sentAt,
    receivedAt,
    kind,
    body,
    payload,
    replyToId,
    replyToAuthor,
    forwarded,
    mentionsMe,
    status,
    editedAt,
    deletedAt,
    expireSeconds,
    expiresAt,
    viewOnceState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_rowid')) {
      context.handle(
        _localRowidMeta,
        localRowid.isAcceptableOrUnknown(data['local_rowid']!, _localRowidMeta),
      );
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender')) {
      context.handle(
        _senderMeta,
        sender.isAcceptableOrUnknown(data['sender']!, _senderMeta),
      );
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('sender_device')) {
      context.handle(
        _senderDeviceMeta,
        senderDevice.isAcceptableOrUnknown(
          data['sender_device']!,
          _senderDeviceMeta,
        ),
      );
    }
    if (data.containsKey('outgoing')) {
      context.handle(
        _outgoingMeta,
        outgoing.isAcceptableOrUnknown(data['outgoing']!, _outgoingMeta),
      );
    } else if (isInserting) {
      context.missing(_outgoingMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sortKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
        _replyToIdMeta,
        replyToId.isAcceptableOrUnknown(data['reply_to_id']!, _replyToIdMeta),
      );
    }
    if (data.containsKey('reply_to_author')) {
      context.handle(
        _replyToAuthorMeta,
        replyToAuthor.isAcceptableOrUnknown(
          data['reply_to_author']!,
          _replyToAuthorMeta,
        ),
      );
    }
    if (data.containsKey('forwarded')) {
      context.handle(
        _forwardedMeta,
        forwarded.isAcceptableOrUnknown(data['forwarded']!, _forwardedMeta),
      );
    }
    if (data.containsKey('mentions_me')) {
      context.handle(
        _mentionsMeMeta,
        mentionsMe.isAcceptableOrUnknown(data['mentions_me']!, _mentionsMeMeta),
      );
    }
    if (data.containsKey('expire_seconds')) {
      context.handle(
        _expireSecondsMeta,
        expireSeconds.isAcceptableOrUnknown(
          data['expire_seconds']!,
          _expireSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localRowid};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {messageId, sender},
    {conversationId, sortKey},
  ];
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      localRowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rowid'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      sender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender'],
      )!,
      senderDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_device'],
      ),
      outgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}outgoing'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
      sentAt: $MessagesTable.$convertersentAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}sent_at'],
        )!,
      ),
      receivedAt: $MessagesTable.$converterreceivedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}received_at'],
        )!,
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      replyToId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_id'],
      ),
      replyToAuthor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_author'],
      ),
      forwarded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}forwarded'],
      )!,
      mentionsMe: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}mentions_me'],
      )!,
      status: $MessagesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      editedAt: $MessagesTable.$convertereditedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}edited_at'],
        ),
      ),
      deletedAt: $MessagesTable.$converterdeletedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      expireSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expire_seconds'],
      ),
      expiresAt: $MessagesTable.$converterexpiresAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}expires_at'],
        ),
      ),
      viewOnceState: $MessagesTable.$converterviewOnceStaten.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}view_once_state'],
        ),
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertersentAt = const EpochMs();
  static TypeConverter<DateTime, int> $converterreceivedAt = const EpochMs();
  static JsonTypeConverter2<MessageStatus, String, String> $converterstatus =
      const EnumNameConverter<MessageStatus>(MessageStatus.values);
  static TypeConverter<DateTime, int> $convertereditedAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $convertereditedAtn =
      NullAwareTypeConverter.wrap($convertereditedAt);
  static TypeConverter<DateTime, int> $converterdeletedAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterdeletedAtn =
      NullAwareTypeConverter.wrap($converterdeletedAt);
  static TypeConverter<DateTime, int> $converterexpiresAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterexpiresAtn =
      NullAwareTypeConverter.wrap($converterexpiresAt);
  static JsonTypeConverter2<ViewOnceState, String, String>
  $converterviewOnceState = const EnumNameConverter<ViewOnceState>(
    ViewOnceState.values,
  );
  static JsonTypeConverter2<ViewOnceState?, String?, String?>
  $converterviewOnceStaten = JsonTypeConverter2.asNullable(
    $converterviewOnceState,
  );
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  /// Local row id; also the FTS rowid.
  final int localRowid;

  /// UUIDv7 chosen by the author. Other content names a message by
  /// `(message_id, sender)`.
  final String messageId;
  final String conversationId;
  final String sender;
  final String? senderDevice;
  final bool outgoing;

  /// [SortKey.of] `(sent_at, message_id)`; keyset paging runs on
  /// `(conversation_id, sort_key)`.
  final String sortKey;
  final DateTime sentAt;
  final DateTime receivedAt;

  /// The content `type` (`text`, `media`, `poll`, …), or a type this client
  /// does not know (shown as "needs a newer version").
  final String kind;

  /// Searchable text: the message text or the media caption. Indexed by
  /// `messages_fts`; cleared on delete for everyone.
  final String? body;

  /// The rest of the content body as JSON (poll options, location, contact
  /// card, link preview, mentions, …).
  final String? payload;
  final String? replyToId;
  final String? replyToAuthor;
  final bool forwarded;
  final bool mentionsMe;
  final MessageStatus status;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  /// Disappearing timer (`exp`), counted from first display on this device;
  /// [expiresAt] is set then.
  final int? expireSeconds;
  final DateTime? expiresAt;
  final ViewOnceState? viewOnceState;
  const MessageRow({
    required this.localRowid,
    required this.messageId,
    required this.conversationId,
    required this.sender,
    this.senderDevice,
    required this.outgoing,
    required this.sortKey,
    required this.sentAt,
    required this.receivedAt,
    required this.kind,
    this.body,
    this.payload,
    this.replyToId,
    this.replyToAuthor,
    required this.forwarded,
    required this.mentionsMe,
    required this.status,
    this.editedAt,
    this.deletedAt,
    this.expireSeconds,
    this.expiresAt,
    this.viewOnceState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_rowid'] = Variable<int>(localRowid);
    map['message_id'] = Variable<String>(messageId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['sender'] = Variable<String>(sender);
    if (!nullToAbsent || senderDevice != null) {
      map['sender_device'] = Variable<String>(senderDevice);
    }
    map['outgoing'] = Variable<bool>(outgoing);
    map['sort_key'] = Variable<String>(sortKey);
    {
      map['sent_at'] = Variable<int>(
        $MessagesTable.$convertersentAt.toSql(sentAt),
      );
    }
    {
      map['received_at'] = Variable<int>(
        $MessagesTable.$converterreceivedAt.toSql(receivedAt),
      );
    }
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    if (!nullToAbsent || replyToAuthor != null) {
      map['reply_to_author'] = Variable<String>(replyToAuthor);
    }
    map['forwarded'] = Variable<bool>(forwarded);
    map['mentions_me'] = Variable<bool>(mentionsMe);
    {
      map['status'] = Variable<String>(
        $MessagesTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || editedAt != null) {
      map['edited_at'] = Variable<int>(
        $MessagesTable.$convertereditedAtn.toSql(editedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(
        $MessagesTable.$converterdeletedAtn.toSql(deletedAt),
      );
    }
    if (!nullToAbsent || expireSeconds != null) {
      map['expire_seconds'] = Variable<int>(expireSeconds);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(
        $MessagesTable.$converterexpiresAtn.toSql(expiresAt),
      );
    }
    if (!nullToAbsent || viewOnceState != null) {
      map['view_once_state'] = Variable<String>(
        $MessagesTable.$converterviewOnceStaten.toSql(viewOnceState),
      );
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      localRowid: Value(localRowid),
      messageId: Value(messageId),
      conversationId: Value(conversationId),
      sender: Value(sender),
      senderDevice: senderDevice == null && nullToAbsent
          ? const Value.absent()
          : Value(senderDevice),
      outgoing: Value(outgoing),
      sortKey: Value(sortKey),
      sentAt: Value(sentAt),
      receivedAt: Value(receivedAt),
      kind: Value(kind),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      replyToAuthor: replyToAuthor == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToAuthor),
      forwarded: Value(forwarded),
      mentionsMe: Value(mentionsMe),
      status: Value(status),
      editedAt: editedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(editedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      expireSeconds: expireSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(expireSeconds),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      viewOnceState: viewOnceState == null && nullToAbsent
          ? const Value.absent()
          : Value(viewOnceState),
    );
  }

  factory MessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      localRowid: serializer.fromJson<int>(json['localRowid']),
      messageId: serializer.fromJson<String>(json['messageId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      sender: serializer.fromJson<String>(json['sender']),
      senderDevice: serializer.fromJson<String?>(json['senderDevice']),
      outgoing: serializer.fromJson<bool>(json['outgoing']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
      sentAt: serializer.fromJson<DateTime>(json['sentAt']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
      kind: serializer.fromJson<String>(json['kind']),
      body: serializer.fromJson<String?>(json['body']),
      payload: serializer.fromJson<String?>(json['payload']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      replyToAuthor: serializer.fromJson<String?>(json['replyToAuthor']),
      forwarded: serializer.fromJson<bool>(json['forwarded']),
      mentionsMe: serializer.fromJson<bool>(json['mentionsMe']),
      status: $MessagesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      editedAt: serializer.fromJson<DateTime?>(json['editedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      expireSeconds: serializer.fromJson<int?>(json['expireSeconds']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      viewOnceState: $MessagesTable.$converterviewOnceStaten.fromJson(
        serializer.fromJson<String?>(json['viewOnceState']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localRowid': serializer.toJson<int>(localRowid),
      'messageId': serializer.toJson<String>(messageId),
      'conversationId': serializer.toJson<String>(conversationId),
      'sender': serializer.toJson<String>(sender),
      'senderDevice': serializer.toJson<String?>(senderDevice),
      'outgoing': serializer.toJson<bool>(outgoing),
      'sortKey': serializer.toJson<String>(sortKey),
      'sentAt': serializer.toJson<DateTime>(sentAt),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
      'kind': serializer.toJson<String>(kind),
      'body': serializer.toJson<String?>(body),
      'payload': serializer.toJson<String?>(payload),
      'replyToId': serializer.toJson<String?>(replyToId),
      'replyToAuthor': serializer.toJson<String?>(replyToAuthor),
      'forwarded': serializer.toJson<bool>(forwarded),
      'mentionsMe': serializer.toJson<bool>(mentionsMe),
      'status': serializer.toJson<String>(
        $MessagesTable.$converterstatus.toJson(status),
      ),
      'editedAt': serializer.toJson<DateTime?>(editedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'expireSeconds': serializer.toJson<int?>(expireSeconds),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'viewOnceState': serializer.toJson<String?>(
        $MessagesTable.$converterviewOnceStaten.toJson(viewOnceState),
      ),
    };
  }

  MessageRow copyWith({
    int? localRowid,
    String? messageId,
    String? conversationId,
    String? sender,
    Value<String?> senderDevice = const Value.absent(),
    bool? outgoing,
    String? sortKey,
    DateTime? sentAt,
    DateTime? receivedAt,
    String? kind,
    Value<String?> body = const Value.absent(),
    Value<String?> payload = const Value.absent(),
    Value<String?> replyToId = const Value.absent(),
    Value<String?> replyToAuthor = const Value.absent(),
    bool? forwarded,
    bool? mentionsMe,
    MessageStatus? status,
    Value<DateTime?> editedAt = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<int?> expireSeconds = const Value.absent(),
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<ViewOnceState?> viewOnceState = const Value.absent(),
  }) => MessageRow(
    localRowid: localRowid ?? this.localRowid,
    messageId: messageId ?? this.messageId,
    conversationId: conversationId ?? this.conversationId,
    sender: sender ?? this.sender,
    senderDevice: senderDevice.present ? senderDevice.value : this.senderDevice,
    outgoing: outgoing ?? this.outgoing,
    sortKey: sortKey ?? this.sortKey,
    sentAt: sentAt ?? this.sentAt,
    receivedAt: receivedAt ?? this.receivedAt,
    kind: kind ?? this.kind,
    body: body.present ? body.value : this.body,
    payload: payload.present ? payload.value : this.payload,
    replyToId: replyToId.present ? replyToId.value : this.replyToId,
    replyToAuthor: replyToAuthor.present
        ? replyToAuthor.value
        : this.replyToAuthor,
    forwarded: forwarded ?? this.forwarded,
    mentionsMe: mentionsMe ?? this.mentionsMe,
    status: status ?? this.status,
    editedAt: editedAt.present ? editedAt.value : this.editedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    expireSeconds: expireSeconds.present
        ? expireSeconds.value
        : this.expireSeconds,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    viewOnceState: viewOnceState.present
        ? viewOnceState.value
        : this.viewOnceState,
  );
  MessageRow copyWithCompanion(MessagesCompanion data) {
    return MessageRow(
      localRowid: data.localRowid.present
          ? data.localRowid.value
          : this.localRowid,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      sender: data.sender.present ? data.sender.value : this.sender,
      senderDevice: data.senderDevice.present
          ? data.senderDevice.value
          : this.senderDevice,
      outgoing: data.outgoing.present ? data.outgoing.value : this.outgoing,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      kind: data.kind.present ? data.kind.value : this.kind,
      body: data.body.present ? data.body.value : this.body,
      payload: data.payload.present ? data.payload.value : this.payload,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      replyToAuthor: data.replyToAuthor.present
          ? data.replyToAuthor.value
          : this.replyToAuthor,
      forwarded: data.forwarded.present ? data.forwarded.value : this.forwarded,
      mentionsMe: data.mentionsMe.present
          ? data.mentionsMe.value
          : this.mentionsMe,
      status: data.status.present ? data.status.value : this.status,
      editedAt: data.editedAt.present ? data.editedAt.value : this.editedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      expireSeconds: data.expireSeconds.present
          ? data.expireSeconds.value
          : this.expireSeconds,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      viewOnceState: data.viewOnceState.present
          ? data.viewOnceState.value
          : this.viewOnceState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('localRowid: $localRowid, ')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('sender: $sender, ')
          ..write('senderDevice: $senderDevice, ')
          ..write('outgoing: $outgoing, ')
          ..write('sortKey: $sortKey, ')
          ..write('sentAt: $sentAt, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('payload: $payload, ')
          ..write('replyToId: $replyToId, ')
          ..write('replyToAuthor: $replyToAuthor, ')
          ..write('forwarded: $forwarded, ')
          ..write('mentionsMe: $mentionsMe, ')
          ..write('status: $status, ')
          ..write('editedAt: $editedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('expireSeconds: $expireSeconds, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('viewOnceState: $viewOnceState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    localRowid,
    messageId,
    conversationId,
    sender,
    senderDevice,
    outgoing,
    sortKey,
    sentAt,
    receivedAt,
    kind,
    body,
    payload,
    replyToId,
    replyToAuthor,
    forwarded,
    mentionsMe,
    status,
    editedAt,
    deletedAt,
    expireSeconds,
    expiresAt,
    viewOnceState,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.localRowid == this.localRowid &&
          other.messageId == this.messageId &&
          other.conversationId == this.conversationId &&
          other.sender == this.sender &&
          other.senderDevice == this.senderDevice &&
          other.outgoing == this.outgoing &&
          other.sortKey == this.sortKey &&
          other.sentAt == this.sentAt &&
          other.receivedAt == this.receivedAt &&
          other.kind == this.kind &&
          other.body == this.body &&
          other.payload == this.payload &&
          other.replyToId == this.replyToId &&
          other.replyToAuthor == this.replyToAuthor &&
          other.forwarded == this.forwarded &&
          other.mentionsMe == this.mentionsMe &&
          other.status == this.status &&
          other.editedAt == this.editedAt &&
          other.deletedAt == this.deletedAt &&
          other.expireSeconds == this.expireSeconds &&
          other.expiresAt == this.expiresAt &&
          other.viewOnceState == this.viewOnceState);
}

class MessagesCompanion extends UpdateCompanion<MessageRow> {
  final Value<int> localRowid;
  final Value<String> messageId;
  final Value<String> conversationId;
  final Value<String> sender;
  final Value<String?> senderDevice;
  final Value<bool> outgoing;
  final Value<String> sortKey;
  final Value<DateTime> sentAt;
  final Value<DateTime> receivedAt;
  final Value<String> kind;
  final Value<String?> body;
  final Value<String?> payload;
  final Value<String?> replyToId;
  final Value<String?> replyToAuthor;
  final Value<bool> forwarded;
  final Value<bool> mentionsMe;
  final Value<MessageStatus> status;
  final Value<DateTime?> editedAt;
  final Value<DateTime?> deletedAt;
  final Value<int?> expireSeconds;
  final Value<DateTime?> expiresAt;
  final Value<ViewOnceState?> viewOnceState;
  const MessagesCompanion({
    this.localRowid = const Value.absent(),
    this.messageId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.sender = const Value.absent(),
    this.senderDevice = const Value.absent(),
    this.outgoing = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.body = const Value.absent(),
    this.payload = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.replyToAuthor = const Value.absent(),
    this.forwarded = const Value.absent(),
    this.mentionsMe = const Value.absent(),
    this.status = const Value.absent(),
    this.editedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.expireSeconds = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.viewOnceState = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.localRowid = const Value.absent(),
    required String messageId,
    required String conversationId,
    required String sender,
    this.senderDevice = const Value.absent(),
    required bool outgoing,
    required String sortKey,
    required DateTime sentAt,
    required DateTime receivedAt,
    required String kind,
    this.body = const Value.absent(),
    this.payload = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.replyToAuthor = const Value.absent(),
    this.forwarded = const Value.absent(),
    this.mentionsMe = const Value.absent(),
    required MessageStatus status,
    this.editedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.expireSeconds = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.viewOnceState = const Value.absent(),
  }) : messageId = Value(messageId),
       conversationId = Value(conversationId),
       sender = Value(sender),
       outgoing = Value(outgoing),
       sortKey = Value(sortKey),
       sentAt = Value(sentAt),
       receivedAt = Value(receivedAt),
       kind = Value(kind),
       status = Value(status);
  static Insertable<MessageRow> custom({
    Expression<int>? localRowid,
    Expression<String>? messageId,
    Expression<String>? conversationId,
    Expression<String>? sender,
    Expression<String>? senderDevice,
    Expression<bool>? outgoing,
    Expression<String>? sortKey,
    Expression<int>? sentAt,
    Expression<int>? receivedAt,
    Expression<String>? kind,
    Expression<String>? body,
    Expression<String>? payload,
    Expression<String>? replyToId,
    Expression<String>? replyToAuthor,
    Expression<bool>? forwarded,
    Expression<bool>? mentionsMe,
    Expression<String>? status,
    Expression<int>? editedAt,
    Expression<int>? deletedAt,
    Expression<int>? expireSeconds,
    Expression<int>? expiresAt,
    Expression<String>? viewOnceState,
  }) {
    return RawValuesInsertable({
      if (localRowid != null) 'local_rowid': localRowid,
      if (messageId != null) 'message_id': messageId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (sender != null) 'sender': sender,
      if (senderDevice != null) 'sender_device': senderDevice,
      if (outgoing != null) 'outgoing': outgoing,
      if (sortKey != null) 'sort_key': sortKey,
      if (sentAt != null) 'sent_at': sentAt,
      if (receivedAt != null) 'received_at': receivedAt,
      if (kind != null) 'kind': kind,
      if (body != null) 'body': body,
      if (payload != null) 'payload': payload,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (replyToAuthor != null) 'reply_to_author': replyToAuthor,
      if (forwarded != null) 'forwarded': forwarded,
      if (mentionsMe != null) 'mentions_me': mentionsMe,
      if (status != null) 'status': status,
      if (editedAt != null) 'edited_at': editedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (expireSeconds != null) 'expire_seconds': expireSeconds,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (viewOnceState != null) 'view_once_state': viewOnceState,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? localRowid,
    Value<String>? messageId,
    Value<String>? conversationId,
    Value<String>? sender,
    Value<String?>? senderDevice,
    Value<bool>? outgoing,
    Value<String>? sortKey,
    Value<DateTime>? sentAt,
    Value<DateTime>? receivedAt,
    Value<String>? kind,
    Value<String?>? body,
    Value<String?>? payload,
    Value<String?>? replyToId,
    Value<String?>? replyToAuthor,
    Value<bool>? forwarded,
    Value<bool>? mentionsMe,
    Value<MessageStatus>? status,
    Value<DateTime?>? editedAt,
    Value<DateTime?>? deletedAt,
    Value<int?>? expireSeconds,
    Value<DateTime?>? expiresAt,
    Value<ViewOnceState?>? viewOnceState,
  }) {
    return MessagesCompanion(
      localRowid: localRowid ?? this.localRowid,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      sender: sender ?? this.sender,
      senderDevice: senderDevice ?? this.senderDevice,
      outgoing: outgoing ?? this.outgoing,
      sortKey: sortKey ?? this.sortKey,
      sentAt: sentAt ?? this.sentAt,
      receivedAt: receivedAt ?? this.receivedAt,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      payload: payload ?? this.payload,
      replyToId: replyToId ?? this.replyToId,
      replyToAuthor: replyToAuthor ?? this.replyToAuthor,
      forwarded: forwarded ?? this.forwarded,
      mentionsMe: mentionsMe ?? this.mentionsMe,
      status: status ?? this.status,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      expireSeconds: expireSeconds ?? this.expireSeconds,
      expiresAt: expiresAt ?? this.expiresAt,
      viewOnceState: viewOnceState ?? this.viewOnceState,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localRowid.present) {
      map['local_rowid'] = Variable<int>(localRowid.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (senderDevice.present) {
      map['sender_device'] = Variable<String>(senderDevice.value);
    }
    if (outgoing.present) {
      map['outgoing'] = Variable<bool>(outgoing.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<int>(
        $MessagesTable.$convertersentAt.toSql(sentAt.value),
      );
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<int>(
        $MessagesTable.$converterreceivedAt.toSql(receivedAt.value),
      );
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (replyToAuthor.present) {
      map['reply_to_author'] = Variable<String>(replyToAuthor.value);
    }
    if (forwarded.present) {
      map['forwarded'] = Variable<bool>(forwarded.value);
    }
    if (mentionsMe.present) {
      map['mentions_me'] = Variable<bool>(mentionsMe.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $MessagesTable.$converterstatus.toSql(status.value),
      );
    }
    if (editedAt.present) {
      map['edited_at'] = Variable<int>(
        $MessagesTable.$convertereditedAtn.toSql(editedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(
        $MessagesTable.$converterdeletedAtn.toSql(deletedAt.value),
      );
    }
    if (expireSeconds.present) {
      map['expire_seconds'] = Variable<int>(expireSeconds.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(
        $MessagesTable.$converterexpiresAtn.toSql(expiresAt.value),
      );
    }
    if (viewOnceState.present) {
      map['view_once_state'] = Variable<String>(
        $MessagesTable.$converterviewOnceStaten.toSql(viewOnceState.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('localRowid: $localRowid, ')
          ..write('messageId: $messageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('sender: $sender, ')
          ..write('senderDevice: $senderDevice, ')
          ..write('outgoing: $outgoing, ')
          ..write('sortKey: $sortKey, ')
          ..write('sentAt: $sentAt, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('payload: $payload, ')
          ..write('replyToId: $replyToId, ')
          ..write('replyToAuthor: $replyToAuthor, ')
          ..write('forwarded: $forwarded, ')
          ..write('mentionsMe: $mentionsMe, ')
          ..write('status: $status, ')
          ..write('editedAt: $editedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('expireSeconds: $expireSeconds, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('viewOnceState: $viewOnceState')
          ..write(')'))
        .toString();
  }
}

class $MessageReactionsTable extends MessageReactions
    with TableInfo<$MessageReactionsTable, ReactionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageReactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageRowidMeta = const VerificationMeta(
    'messageRowid',
  );
  @override
  late final GeneratedColumn<int> messageRowid = GeneratedColumn<int>(
    'message_rowid',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (local_rowid) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _reactorMeta = const VerificationMeta(
    'reactor',
  );
  @override
  late final GeneratedColumn<String> reactor = GeneratedColumn<String>(
    'reactor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> reactedAt =
      GeneratedColumn<int>(
        'reacted_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($MessageReactionsTable.$converterreactedAt);
  @override
  List<GeneratedColumn> get $columns => [
    messageRowid,
    reactor,
    emoji,
    reactedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_reactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReactionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_rowid')) {
      context.handle(
        _messageRowidMeta,
        messageRowid.isAcceptableOrUnknown(
          data['message_rowid']!,
          _messageRowidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageRowidMeta);
    }
    if (data.containsKey('reactor')) {
      context.handle(
        _reactorMeta,
        reactor.isAcceptableOrUnknown(data['reactor']!, _reactorMeta),
      );
    } else if (isInserting) {
      context.missing(_reactorMeta);
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    } else if (isInserting) {
      context.missing(_emojiMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageRowid, reactor};
  @override
  ReactionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReactionRow(
      messageRowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_rowid'],
      )!,
      reactor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reactor'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      reactedAt: $MessageReactionsTable.$converterreactedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}reacted_at'],
        )!,
      ),
    );
  }

  @override
  $MessageReactionsTable createAlias(String alias) {
    return $MessageReactionsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterreactedAt = const EpochMs();
}

class ReactionRow extends DataClass implements Insertable<ReactionRow> {
  final int messageRowid;
  final String reactor;
  final String emoji;
  final DateTime reactedAt;
  const ReactionRow({
    required this.messageRowid,
    required this.reactor,
    required this.emoji,
    required this.reactedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_rowid'] = Variable<int>(messageRowid);
    map['reactor'] = Variable<String>(reactor);
    map['emoji'] = Variable<String>(emoji);
    {
      map['reacted_at'] = Variable<int>(
        $MessageReactionsTable.$converterreactedAt.toSql(reactedAt),
      );
    }
    return map;
  }

  MessageReactionsCompanion toCompanion(bool nullToAbsent) {
    return MessageReactionsCompanion(
      messageRowid: Value(messageRowid),
      reactor: Value(reactor),
      emoji: Value(emoji),
      reactedAt: Value(reactedAt),
    );
  }

  factory ReactionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReactionRow(
      messageRowid: serializer.fromJson<int>(json['messageRowid']),
      reactor: serializer.fromJson<String>(json['reactor']),
      emoji: serializer.fromJson<String>(json['emoji']),
      reactedAt: serializer.fromJson<DateTime>(json['reactedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageRowid': serializer.toJson<int>(messageRowid),
      'reactor': serializer.toJson<String>(reactor),
      'emoji': serializer.toJson<String>(emoji),
      'reactedAt': serializer.toJson<DateTime>(reactedAt),
    };
  }

  ReactionRow copyWith({
    int? messageRowid,
    String? reactor,
    String? emoji,
    DateTime? reactedAt,
  }) => ReactionRow(
    messageRowid: messageRowid ?? this.messageRowid,
    reactor: reactor ?? this.reactor,
    emoji: emoji ?? this.emoji,
    reactedAt: reactedAt ?? this.reactedAt,
  );
  ReactionRow copyWithCompanion(MessageReactionsCompanion data) {
    return ReactionRow(
      messageRowid: data.messageRowid.present
          ? data.messageRowid.value
          : this.messageRowid,
      reactor: data.reactor.present ? data.reactor.value : this.reactor,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      reactedAt: data.reactedAt.present ? data.reactedAt.value : this.reactedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReactionRow(')
          ..write('messageRowid: $messageRowid, ')
          ..write('reactor: $reactor, ')
          ..write('emoji: $emoji, ')
          ..write('reactedAt: $reactedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(messageRowid, reactor, emoji, reactedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReactionRow &&
          other.messageRowid == this.messageRowid &&
          other.reactor == this.reactor &&
          other.emoji == this.emoji &&
          other.reactedAt == this.reactedAt);
}

class MessageReactionsCompanion extends UpdateCompanion<ReactionRow> {
  final Value<int> messageRowid;
  final Value<String> reactor;
  final Value<String> emoji;
  final Value<DateTime> reactedAt;
  final Value<int> rowid;
  const MessageReactionsCompanion({
    this.messageRowid = const Value.absent(),
    this.reactor = const Value.absent(),
    this.emoji = const Value.absent(),
    this.reactedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageReactionsCompanion.insert({
    required int messageRowid,
    required String reactor,
    required String emoji,
    required DateTime reactedAt,
    this.rowid = const Value.absent(),
  }) : messageRowid = Value(messageRowid),
       reactor = Value(reactor),
       emoji = Value(emoji),
       reactedAt = Value(reactedAt);
  static Insertable<ReactionRow> custom({
    Expression<int>? messageRowid,
    Expression<String>? reactor,
    Expression<String>? emoji,
    Expression<int>? reactedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageRowid != null) 'message_rowid': messageRowid,
      if (reactor != null) 'reactor': reactor,
      if (emoji != null) 'emoji': emoji,
      if (reactedAt != null) 'reacted_at': reactedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageReactionsCompanion copyWith({
    Value<int>? messageRowid,
    Value<String>? reactor,
    Value<String>? emoji,
    Value<DateTime>? reactedAt,
    Value<int>? rowid,
  }) {
    return MessageReactionsCompanion(
      messageRowid: messageRowid ?? this.messageRowid,
      reactor: reactor ?? this.reactor,
      emoji: emoji ?? this.emoji,
      reactedAt: reactedAt ?? this.reactedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageRowid.present) {
      map['message_rowid'] = Variable<int>(messageRowid.value);
    }
    if (reactor.present) {
      map['reactor'] = Variable<String>(reactor.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (reactedAt.present) {
      map['reacted_at'] = Variable<int>(
        $MessageReactionsTable.$converterreactedAt.toSql(reactedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageReactionsCompanion(')
          ..write('messageRowid: $messageRowid, ')
          ..write('reactor: $reactor, ')
          ..write('emoji: $emoji, ')
          ..write('reactedAt: $reactedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageReceiptsTable extends MessageReceipts
    with TableInfo<$MessageReceiptsTable, ReceiptRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageRowidMeta = const VerificationMeta(
    'messageRowid',
  );
  @override
  late final GeneratedColumn<int> messageRowid = GeneratedColumn<int>(
    'message_rowid',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (local_rowid) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> deliveredAt =
      GeneratedColumn<int>(
        'delivered_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($MessageReceiptsTable.$converterdeliveredAtn);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> readAt =
      GeneratedColumn<int>(
        'read_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($MessageReceiptsTable.$converterreadAtn);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> viewedAt =
      GeneratedColumn<int>(
        'viewed_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($MessageReceiptsTable.$converterviewedAtn);
  @override
  List<GeneratedColumn> get $columns => [
    messageRowid,
    accountId,
    deliveredAt,
    readAt,
    viewedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceiptRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_rowid')) {
      context.handle(
        _messageRowidMeta,
        messageRowid.isAcceptableOrUnknown(
          data['message_rowid']!,
          _messageRowidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageRowidMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageRowid, accountId};
  @override
  ReceiptRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceiptRow(
      messageRowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_rowid'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      deliveredAt: $MessageReceiptsTable.$converterdeliveredAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}delivered_at'],
        ),
      ),
      readAt: $MessageReceiptsTable.$converterreadAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}read_at'],
        ),
      ),
      viewedAt: $MessageReceiptsTable.$converterviewedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}viewed_at'],
        ),
      ),
    );
  }

  @override
  $MessageReceiptsTable createAlias(String alias) {
    return $MessageReceiptsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterdeliveredAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterdeliveredAtn =
      NullAwareTypeConverter.wrap($converterdeliveredAt);
  static TypeConverter<DateTime, int> $converterreadAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterreadAtn =
      NullAwareTypeConverter.wrap($converterreadAt);
  static TypeConverter<DateTime, int> $converterviewedAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterviewedAtn =
      NullAwareTypeConverter.wrap($converterviewedAt);
}

class ReceiptRow extends DataClass implements Insertable<ReceiptRow> {
  final int messageRowid;
  final String accountId;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? viewedAt;
  const ReceiptRow({
    required this.messageRowid,
    required this.accountId,
    this.deliveredAt,
    this.readAt,
    this.viewedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_rowid'] = Variable<int>(messageRowid);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<int>(
        $MessageReceiptsTable.$converterdeliveredAtn.toSql(deliveredAt),
      );
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<int>(
        $MessageReceiptsTable.$converterreadAtn.toSql(readAt),
      );
    }
    if (!nullToAbsent || viewedAt != null) {
      map['viewed_at'] = Variable<int>(
        $MessageReceiptsTable.$converterviewedAtn.toSql(viewedAt),
      );
    }
    return map;
  }

  MessageReceiptsCompanion toCompanion(bool nullToAbsent) {
    return MessageReceiptsCompanion(
      messageRowid: Value(messageRowid),
      accountId: Value(accountId),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
      viewedAt: viewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(viewedAt),
    );
  }

  factory ReceiptRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceiptRow(
      messageRowid: serializer.fromJson<int>(json['messageRowid']),
      accountId: serializer.fromJson<String>(json['accountId']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
      viewedAt: serializer.fromJson<DateTime?>(json['viewedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageRowid': serializer.toJson<int>(messageRowid),
      'accountId': serializer.toJson<String>(accountId),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'readAt': serializer.toJson<DateTime?>(readAt),
      'viewedAt': serializer.toJson<DateTime?>(viewedAt),
    };
  }

  ReceiptRow copyWith({
    int? messageRowid,
    String? accountId,
    Value<DateTime?> deliveredAt = const Value.absent(),
    Value<DateTime?> readAt = const Value.absent(),
    Value<DateTime?> viewedAt = const Value.absent(),
  }) => ReceiptRow(
    messageRowid: messageRowid ?? this.messageRowid,
    accountId: accountId ?? this.accountId,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    readAt: readAt.present ? readAt.value : this.readAt,
    viewedAt: viewedAt.present ? viewedAt.value : this.viewedAt,
  );
  ReceiptRow copyWithCompanion(MessageReceiptsCompanion data) {
    return ReceiptRow(
      messageRowid: data.messageRowid.present
          ? data.messageRowid.value
          : this.messageRowid,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      viewedAt: data.viewedAt.present ? data.viewedAt.value : this.viewedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptRow(')
          ..write('messageRowid: $messageRowid, ')
          ..write('accountId: $accountId, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt, ')
          ..write('viewedAt: $viewedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(messageRowid, accountId, deliveredAt, readAt, viewedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceiptRow &&
          other.messageRowid == this.messageRowid &&
          other.accountId == this.accountId &&
          other.deliveredAt == this.deliveredAt &&
          other.readAt == this.readAt &&
          other.viewedAt == this.viewedAt);
}

class MessageReceiptsCompanion extends UpdateCompanion<ReceiptRow> {
  final Value<int> messageRowid;
  final Value<String> accountId;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime?> readAt;
  final Value<DateTime?> viewedAt;
  final Value<int> rowid;
  const MessageReceiptsCompanion({
    this.messageRowid = const Value.absent(),
    this.accountId = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.viewedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageReceiptsCompanion.insert({
    required int messageRowid,
    required String accountId,
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.viewedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : messageRowid = Value(messageRowid),
       accountId = Value(accountId);
  static Insertable<ReceiptRow> custom({
    Expression<int>? messageRowid,
    Expression<String>? accountId,
    Expression<int>? deliveredAt,
    Expression<int>? readAt,
    Expression<int>? viewedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageRowid != null) 'message_rowid': messageRowid,
      if (accountId != null) 'account_id': accountId,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (readAt != null) 'read_at': readAt,
      if (viewedAt != null) 'viewed_at': viewedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageReceiptsCompanion copyWith({
    Value<int>? messageRowid,
    Value<String>? accountId,
    Value<DateTime?>? deliveredAt,
    Value<DateTime?>? readAt,
    Value<DateTime?>? viewedAt,
    Value<int>? rowid,
  }) {
    return MessageReceiptsCompanion(
      messageRowid: messageRowid ?? this.messageRowid,
      accountId: accountId ?? this.accountId,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      viewedAt: viewedAt ?? this.viewedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageRowid.present) {
      map['message_rowid'] = Variable<int>(messageRowid.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<int>(
        $MessageReceiptsTable.$converterdeliveredAtn.toSql(deliveredAt.value),
      );
    }
    if (readAt.present) {
      map['read_at'] = Variable<int>(
        $MessageReceiptsTable.$converterreadAtn.toSql(readAt.value),
      );
    }
    if (viewedAt.present) {
      map['viewed_at'] = Variable<int>(
        $MessageReceiptsTable.$converterviewedAtn.toSql(viewedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageReceiptsCompanion(')
          ..write('messageRowid: $messageRowid, ')
          ..write('accountId: $accountId, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt, ')
          ..write('viewedAt: $viewedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentsTable extends Attachments
    with TableInfo<$AttachmentsTable, AttachmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _messageRowidMeta = const VerificationMeta(
    'messageRowid',
  );
  @override
  late final GeneratedColumn<int> messageRowid = GeneratedColumn<int>(
    'message_rowid',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (local_rowid) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaKeyMeta = const VerificationMeta(
    'mediaKey',
  );
  @override
  late final GeneratedColumn<Uint8List> mediaKey = GeneratedColumn<Uint8List>(
    'media_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _digestMeta = const VerificationMeta('digest');
  @override
  late final GeneratedColumn<Uint8List> digest = GeneratedColumn<Uint8List>(
    'digest',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _waveformMeta = const VerificationMeta(
    'waveform',
  );
  @override
  late final GeneratedColumn<Uint8List> waveform = GeneratedColumn<Uint8List>(
    'waveform',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _blurhashMeta = const VerificationMeta(
    'blurhash',
  );
  @override
  late final GeneratedColumn<String> blurhash = GeneratedColumn<String>(
    'blurhash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _captionMeta = const VerificationMeta(
    'caption',
  );
  @override
  late final GeneratedColumn<String> caption = GeneratedColumn<String>(
    'caption',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailMeta = const VerificationMeta(
    'thumbnail',
  );
  @override
  late final GeneratedColumn<String> thumbnail = GeneratedColumn<String>(
    'thumbnail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AttachmentTransfer, String>
  transfer = GeneratedColumn<String>(
    'transfer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<AttachmentTransfer>($AttachmentsTable.$convertertransfer);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageRowid,
    position,
    kind,
    mediaId,
    mediaKey,
    digest,
    mime,
    size,
    name,
    width,
    height,
    durationMs,
    waveform,
    blurhash,
    caption,
    thumbnail,
    thumbnailPath,
    localPath,
    transfer,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachmentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message_rowid')) {
      context.handle(
        _messageRowidMeta,
        messageRowid.isAcceptableOrUnknown(
          data['message_rowid']!,
          _messageRowidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageRowidMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('media_key')) {
      context.handle(
        _mediaKeyMeta,
        mediaKey.isAcceptableOrUnknown(data['media_key']!, _mediaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKeyMeta);
    }
    if (data.containsKey('digest')) {
      context.handle(
        _digestMeta,
        digest.isAcceptableOrUnknown(data['digest']!, _digestMeta),
      );
    } else if (isInserting) {
      context.missing(_digestMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('waveform')) {
      context.handle(
        _waveformMeta,
        waveform.isAcceptableOrUnknown(data['waveform']!, _waveformMeta),
      );
    }
    if (data.containsKey('blurhash')) {
      context.handle(
        _blurhashMeta,
        blurhash.isAcceptableOrUnknown(data['blurhash']!, _blurhashMeta),
      );
    }
    if (data.containsKey('caption')) {
      context.handle(
        _captionMeta,
        caption.isAcceptableOrUnknown(data['caption']!, _captionMeta),
      );
    }
    if (data.containsKey('thumbnail')) {
      context.handle(
        _thumbnailMeta,
        thumbnail.isAcceptableOrUnknown(data['thumbnail']!, _thumbnailMeta),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {messageRowid, position},
  ];
  @override
  AttachmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachmentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      messageRowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_rowid'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      mediaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}media_key'],
      )!,
      digest: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}digest'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      waveform: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}waveform'],
      ),
      blurhash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blurhash'],
      ),
      caption: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caption'],
      ),
      thumbnail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      transfer: $AttachmentsTable.$convertertransfer.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}transfer'],
        )!,
      ),
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AttachmentTransfer, String, String>
  $convertertransfer = const EnumNameConverter<AttachmentTransfer>(
    AttachmentTransfer.values,
  );
}

class AttachmentRow extends DataClass implements Insertable<AttachmentRow> {
  final int id;
  final int messageRowid;
  final int position;

  /// `MediaItemKind` wire name (`image`, `voice_note`, …).
  final String kind;

  /// Server object id and the pointer's key material (CRYPTO_V2.md §12).
  final String mediaId;
  final Uint8List mediaKey;
  final Uint8List digest;
  final String mime;
  final int size;
  final String? name;
  final int? width;
  final int? height;
  final int? durationMs;
  final Uint8List? waveform;
  final String? blurhash;
  final String? caption;

  /// The thumbnail's `MediaPointer` as JSON.
  final String? thumbnail;
  final String? thumbnailPath;
  final String? localPath;
  final AttachmentTransfer transfer;
  const AttachmentRow({
    required this.id,
    required this.messageRowid,
    required this.position,
    required this.kind,
    required this.mediaId,
    required this.mediaKey,
    required this.digest,
    required this.mime,
    required this.size,
    this.name,
    this.width,
    this.height,
    this.durationMs,
    this.waveform,
    this.blurhash,
    this.caption,
    this.thumbnail,
    this.thumbnailPath,
    this.localPath,
    required this.transfer,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['message_rowid'] = Variable<int>(messageRowid);
    map['position'] = Variable<int>(position);
    map['kind'] = Variable<String>(kind);
    map['media_id'] = Variable<String>(mediaId);
    map['media_key'] = Variable<Uint8List>(mediaKey);
    map['digest'] = Variable<Uint8List>(digest);
    map['mime'] = Variable<String>(mime);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || waveform != null) {
      map['waveform'] = Variable<Uint8List>(waveform);
    }
    if (!nullToAbsent || blurhash != null) {
      map['blurhash'] = Variable<String>(blurhash);
    }
    if (!nullToAbsent || caption != null) {
      map['caption'] = Variable<String>(caption);
    }
    if (!nullToAbsent || thumbnail != null) {
      map['thumbnail'] = Variable<String>(thumbnail);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    {
      map['transfer'] = Variable<String>(
        $AttachmentsTable.$convertertransfer.toSql(transfer),
      );
    }
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      id: Value(id),
      messageRowid: Value(messageRowid),
      position: Value(position),
      kind: Value(kind),
      mediaId: Value(mediaId),
      mediaKey: Value(mediaKey),
      digest: Value(digest),
      mime: Value(mime),
      size: Value(size),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      waveform: waveform == null && nullToAbsent
          ? const Value.absent()
          : Value(waveform),
      blurhash: blurhash == null && nullToAbsent
          ? const Value.absent()
          : Value(blurhash),
      caption: caption == null && nullToAbsent
          ? const Value.absent()
          : Value(caption),
      thumbnail: thumbnail == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnail),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      transfer: Value(transfer),
    );
  }

  factory AttachmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachmentRow(
      id: serializer.fromJson<int>(json['id']),
      messageRowid: serializer.fromJson<int>(json['messageRowid']),
      position: serializer.fromJson<int>(json['position']),
      kind: serializer.fromJson<String>(json['kind']),
      mediaId: serializer.fromJson<String>(json['mediaId']),
      mediaKey: serializer.fromJson<Uint8List>(json['mediaKey']),
      digest: serializer.fromJson<Uint8List>(json['digest']),
      mime: serializer.fromJson<String>(json['mime']),
      size: serializer.fromJson<int>(json['size']),
      name: serializer.fromJson<String?>(json['name']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      waveform: serializer.fromJson<Uint8List?>(json['waveform']),
      blurhash: serializer.fromJson<String?>(json['blurhash']),
      caption: serializer.fromJson<String?>(json['caption']),
      thumbnail: serializer.fromJson<String?>(json['thumbnail']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      transfer: $AttachmentsTable.$convertertransfer.fromJson(
        serializer.fromJson<String>(json['transfer']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'messageRowid': serializer.toJson<int>(messageRowid),
      'position': serializer.toJson<int>(position),
      'kind': serializer.toJson<String>(kind),
      'mediaId': serializer.toJson<String>(mediaId),
      'mediaKey': serializer.toJson<Uint8List>(mediaKey),
      'digest': serializer.toJson<Uint8List>(digest),
      'mime': serializer.toJson<String>(mime),
      'size': serializer.toJson<int>(size),
      'name': serializer.toJson<String?>(name),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'durationMs': serializer.toJson<int?>(durationMs),
      'waveform': serializer.toJson<Uint8List?>(waveform),
      'blurhash': serializer.toJson<String?>(blurhash),
      'caption': serializer.toJson<String?>(caption),
      'thumbnail': serializer.toJson<String?>(thumbnail),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'localPath': serializer.toJson<String?>(localPath),
      'transfer': serializer.toJson<String>(
        $AttachmentsTable.$convertertransfer.toJson(transfer),
      ),
    };
  }

  AttachmentRow copyWith({
    int? id,
    int? messageRowid,
    int? position,
    String? kind,
    String? mediaId,
    Uint8List? mediaKey,
    Uint8List? digest,
    String? mime,
    int? size,
    Value<String?> name = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<Uint8List?> waveform = const Value.absent(),
    Value<String?> blurhash = const Value.absent(),
    Value<String?> caption = const Value.absent(),
    Value<String?> thumbnail = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    AttachmentTransfer? transfer,
  }) => AttachmentRow(
    id: id ?? this.id,
    messageRowid: messageRowid ?? this.messageRowid,
    position: position ?? this.position,
    kind: kind ?? this.kind,
    mediaId: mediaId ?? this.mediaId,
    mediaKey: mediaKey ?? this.mediaKey,
    digest: digest ?? this.digest,
    mime: mime ?? this.mime,
    size: size ?? this.size,
    name: name.present ? name.value : this.name,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    waveform: waveform.present ? waveform.value : this.waveform,
    blurhash: blurhash.present ? blurhash.value : this.blurhash,
    caption: caption.present ? caption.value : this.caption,
    thumbnail: thumbnail.present ? thumbnail.value : this.thumbnail,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    localPath: localPath.present ? localPath.value : this.localPath,
    transfer: transfer ?? this.transfer,
  );
  AttachmentRow copyWithCompanion(AttachmentsCompanion data) {
    return AttachmentRow(
      id: data.id.present ? data.id.value : this.id,
      messageRowid: data.messageRowid.present
          ? data.messageRowid.value
          : this.messageRowid,
      position: data.position.present ? data.position.value : this.position,
      kind: data.kind.present ? data.kind.value : this.kind,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      mediaKey: data.mediaKey.present ? data.mediaKey.value : this.mediaKey,
      digest: data.digest.present ? data.digest.value : this.digest,
      mime: data.mime.present ? data.mime.value : this.mime,
      size: data.size.present ? data.size.value : this.size,
      name: data.name.present ? data.name.value : this.name,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      waveform: data.waveform.present ? data.waveform.value : this.waveform,
      blurhash: data.blurhash.present ? data.blurhash.value : this.blurhash,
      caption: data.caption.present ? data.caption.value : this.caption,
      thumbnail: data.thumbnail.present ? data.thumbnail.value : this.thumbnail,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      transfer: data.transfer.present ? data.transfer.value : this.transfer,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentRow(')
          ..write('id: $id, ')
          ..write('messageRowid: $messageRowid, ')
          ..write('position: $position, ')
          ..write('kind: $kind, ')
          ..write('mediaId: $mediaId, ')
          ..write('mediaKey: $mediaKey, ')
          ..write('digest: $digest, ')
          ..write('mime: $mime, ')
          ..write('size: $size, ')
          ..write('name: $name, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('waveform: $waveform, ')
          ..write('blurhash: $blurhash, ')
          ..write('caption: $caption, ')
          ..write('thumbnail: $thumbnail, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('localPath: $localPath, ')
          ..write('transfer: $transfer')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageRowid,
    position,
    kind,
    mediaId,
    $driftBlobEquality.hash(mediaKey),
    $driftBlobEquality.hash(digest),
    mime,
    size,
    name,
    width,
    height,
    durationMs,
    $driftBlobEquality.hash(waveform),
    blurhash,
    caption,
    thumbnail,
    thumbnailPath,
    localPath,
    transfer,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachmentRow &&
          other.id == this.id &&
          other.messageRowid == this.messageRowid &&
          other.position == this.position &&
          other.kind == this.kind &&
          other.mediaId == this.mediaId &&
          $driftBlobEquality.equals(other.mediaKey, this.mediaKey) &&
          $driftBlobEquality.equals(other.digest, this.digest) &&
          other.mime == this.mime &&
          other.size == this.size &&
          other.name == this.name &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          $driftBlobEquality.equals(other.waveform, this.waveform) &&
          other.blurhash == this.blurhash &&
          other.caption == this.caption &&
          other.thumbnail == this.thumbnail &&
          other.thumbnailPath == this.thumbnailPath &&
          other.localPath == this.localPath &&
          other.transfer == this.transfer);
}

class AttachmentsCompanion extends UpdateCompanion<AttachmentRow> {
  final Value<int> id;
  final Value<int> messageRowid;
  final Value<int> position;
  final Value<String> kind;
  final Value<String> mediaId;
  final Value<Uint8List> mediaKey;
  final Value<Uint8List> digest;
  final Value<String> mime;
  final Value<int> size;
  final Value<String?> name;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> durationMs;
  final Value<Uint8List?> waveform;
  final Value<String?> blurhash;
  final Value<String?> caption;
  final Value<String?> thumbnail;
  final Value<String?> thumbnailPath;
  final Value<String?> localPath;
  final Value<AttachmentTransfer> transfer;
  const AttachmentsCompanion({
    this.id = const Value.absent(),
    this.messageRowid = const Value.absent(),
    this.position = const Value.absent(),
    this.kind = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.mediaKey = const Value.absent(),
    this.digest = const Value.absent(),
    this.mime = const Value.absent(),
    this.size = const Value.absent(),
    this.name = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.waveform = const Value.absent(),
    this.blurhash = const Value.absent(),
    this.caption = const Value.absent(),
    this.thumbnail = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.localPath = const Value.absent(),
    this.transfer = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    this.id = const Value.absent(),
    required int messageRowid,
    required int position,
    required String kind,
    required String mediaId,
    required Uint8List mediaKey,
    required Uint8List digest,
    required String mime,
    required int size,
    this.name = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.waveform = const Value.absent(),
    this.blurhash = const Value.absent(),
    this.caption = const Value.absent(),
    this.thumbnail = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.localPath = const Value.absent(),
    required AttachmentTransfer transfer,
  }) : messageRowid = Value(messageRowid),
       position = Value(position),
       kind = Value(kind),
       mediaId = Value(mediaId),
       mediaKey = Value(mediaKey),
       digest = Value(digest),
       mime = Value(mime),
       size = Value(size),
       transfer = Value(transfer);
  static Insertable<AttachmentRow> custom({
    Expression<int>? id,
    Expression<int>? messageRowid,
    Expression<int>? position,
    Expression<String>? kind,
    Expression<String>? mediaId,
    Expression<Uint8List>? mediaKey,
    Expression<Uint8List>? digest,
    Expression<String>? mime,
    Expression<int>? size,
    Expression<String>? name,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<Uint8List>? waveform,
    Expression<String>? blurhash,
    Expression<String>? caption,
    Expression<String>? thumbnail,
    Expression<String>? thumbnailPath,
    Expression<String>? localPath,
    Expression<String>? transfer,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageRowid != null) 'message_rowid': messageRowid,
      if (position != null) 'position': position,
      if (kind != null) 'kind': kind,
      if (mediaId != null) 'media_id': mediaId,
      if (mediaKey != null) 'media_key': mediaKey,
      if (digest != null) 'digest': digest,
      if (mime != null) 'mime': mime,
      if (size != null) 'size': size,
      if (name != null) 'name': name,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (waveform != null) 'waveform': waveform,
      if (blurhash != null) 'blurhash': blurhash,
      if (caption != null) 'caption': caption,
      if (thumbnail != null) 'thumbnail': thumbnail,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (localPath != null) 'local_path': localPath,
      if (transfer != null) 'transfer': transfer,
    });
  }

  AttachmentsCompanion copyWith({
    Value<int>? id,
    Value<int>? messageRowid,
    Value<int>? position,
    Value<String>? kind,
    Value<String>? mediaId,
    Value<Uint8List>? mediaKey,
    Value<Uint8List>? digest,
    Value<String>? mime,
    Value<int>? size,
    Value<String?>? name,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? durationMs,
    Value<Uint8List?>? waveform,
    Value<String?>? blurhash,
    Value<String?>? caption,
    Value<String?>? thumbnail,
    Value<String?>? thumbnailPath,
    Value<String?>? localPath,
    Value<AttachmentTransfer>? transfer,
  }) {
    return AttachmentsCompanion(
      id: id ?? this.id,
      messageRowid: messageRowid ?? this.messageRowid,
      position: position ?? this.position,
      kind: kind ?? this.kind,
      mediaId: mediaId ?? this.mediaId,
      mediaKey: mediaKey ?? this.mediaKey,
      digest: digest ?? this.digest,
      mime: mime ?? this.mime,
      size: size ?? this.size,
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      waveform: waveform ?? this.waveform,
      blurhash: blurhash ?? this.blurhash,
      caption: caption ?? this.caption,
      thumbnail: thumbnail ?? this.thumbnail,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      localPath: localPath ?? this.localPath,
      transfer: transfer ?? this.transfer,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (messageRowid.present) {
      map['message_rowid'] = Variable<int>(messageRowid.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (mediaKey.present) {
      map['media_key'] = Variable<Uint8List>(mediaKey.value);
    }
    if (digest.present) {
      map['digest'] = Variable<Uint8List>(digest.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (waveform.present) {
      map['waveform'] = Variable<Uint8List>(waveform.value);
    }
    if (blurhash.present) {
      map['blurhash'] = Variable<String>(blurhash.value);
    }
    if (caption.present) {
      map['caption'] = Variable<String>(caption.value);
    }
    if (thumbnail.present) {
      map['thumbnail'] = Variable<String>(thumbnail.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (transfer.present) {
      map['transfer'] = Variable<String>(
        $AttachmentsTable.$convertertransfer.toSql(transfer.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('messageRowid: $messageRowid, ')
          ..write('position: $position, ')
          ..write('kind: $kind, ')
          ..write('mediaId: $mediaId, ')
          ..write('mediaKey: $mediaKey, ')
          ..write('digest: $digest, ')
          ..write('mime: $mime, ')
          ..write('size: $size, ')
          ..write('name: $name, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('waveform: $waveform, ')
          ..write('blurhash: $blurhash, ')
          ..write('caption: $caption, ')
          ..write('thumbnail: $thumbnail, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('localPath: $localPath, ')
          ..write('transfer: $transfer')
          ..write(')'))
        .toString();
  }
}

class $ConversationMembersTable extends ConversationMembers
    with TableInfo<$ConversationMembersTable, ConversationMemberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> joinedAt =
      GeneratedColumn<int>(
        'joined_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($ConversationMembersTable.$converterjoinedAtn);
  @override
  List<GeneratedColumn> get $columns => [conversationId, accountId, joinedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversation_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationMemberRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId, accountId};
  @override
  ConversationMemberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationMemberRow(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      joinedAt: $ConversationMembersTable.$converterjoinedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}joined_at'],
        ),
      ),
    );
  }

  @override
  $ConversationMembersTable createAlias(String alias) {
    return $ConversationMembersTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterjoinedAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterjoinedAtn =
      NullAwareTypeConverter.wrap($converterjoinedAt);
}

class ConversationMemberRow extends DataClass
    implements Insertable<ConversationMemberRow> {
  final String conversationId;
  final String accountId;
  final DateTime? joinedAt;
  const ConversationMemberRow({
    required this.conversationId,
    required this.accountId,
    this.joinedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || joinedAt != null) {
      map['joined_at'] = Variable<int>(
        $ConversationMembersTable.$converterjoinedAtn.toSql(joinedAt),
      );
    }
    return map;
  }

  ConversationMembersCompanion toCompanion(bool nullToAbsent) {
    return ConversationMembersCompanion(
      conversationId: Value(conversationId),
      accountId: Value(accountId),
      joinedAt: joinedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(joinedAt),
    );
  }

  factory ConversationMemberRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationMemberRow(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      joinedAt: serializer.fromJson<DateTime?>(json['joinedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'accountId': serializer.toJson<String>(accountId),
      'joinedAt': serializer.toJson<DateTime?>(joinedAt),
    };
  }

  ConversationMemberRow copyWith({
    String? conversationId,
    String? accountId,
    Value<DateTime?> joinedAt = const Value.absent(),
  }) => ConversationMemberRow(
    conversationId: conversationId ?? this.conversationId,
    accountId: accountId ?? this.accountId,
    joinedAt: joinedAt.present ? joinedAt.value : this.joinedAt,
  );
  ConversationMemberRow copyWithCompanion(ConversationMembersCompanion data) {
    return ConversationMemberRow(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      joinedAt: data.joinedAt.present ? data.joinedAt.value : this.joinedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationMemberRow(')
          ..write('conversationId: $conversationId, ')
          ..write('accountId: $accountId, ')
          ..write('joinedAt: $joinedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(conversationId, accountId, joinedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationMemberRow &&
          other.conversationId == this.conversationId &&
          other.accountId == this.accountId &&
          other.joinedAt == this.joinedAt);
}

class ConversationMembersCompanion
    extends UpdateCompanion<ConversationMemberRow> {
  final Value<String> conversationId;
  final Value<String> accountId;
  final Value<DateTime?> joinedAt;
  final Value<int> rowid;
  const ConversationMembersCompanion({
    this.conversationId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.joinedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationMembersCompanion.insert({
    required String conversationId,
    required String accountId,
    this.joinedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       accountId = Value(accountId);
  static Insertable<ConversationMemberRow> custom({
    Expression<String>? conversationId,
    Expression<String>? accountId,
    Expression<int>? joinedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (accountId != null) 'account_id': accountId,
      if (joinedAt != null) 'joined_at': joinedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationMembersCompanion copyWith({
    Value<String>? conversationId,
    Value<String>? accountId,
    Value<DateTime?>? joinedAt,
    Value<int>? rowid,
  }) {
    return ConversationMembersCompanion(
      conversationId: conversationId ?? this.conversationId,
      accountId: accountId ?? this.accountId,
      joinedAt: joinedAt ?? this.joinedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (joinedAt.present) {
      map['joined_at'] = Variable<int>(
        $ConversationMembersTable.$converterjoinedAtn.toSql(joinedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationMembersCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('accountId: $accountId, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SelfAccountTable extends SelfAccount
    with TableInfo<$SelfAccountTable, SelfAccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SelfAccountTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverDomainMeta = const VerificationMeta(
    'serverDomain',
  );
  @override
  late final GeneratedColumn<String> serverDomain = GeneratedColumn<String>(
    'server_domain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _helixNameMeta = const VerificationMeta(
    'helixName',
  );
  @override
  late final GeneratedColumn<String> helixName = GeneratedColumn<String>(
    'helix_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneNumberMeta = const VerificationMeta(
    'phoneNumber',
  );
  @override
  late final GeneratedColumn<String> phoneNumber = GeneratedColumn<String>(
    'phone_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileNameMeta = const VerificationMeta(
    'profileName',
  );
  @override
  late final GeneratedColumn<String> profileName = GeneratedColumn<String>(
    'profile_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileKeyMeta = const VerificationMeta(
    'profileKey',
  );
  @override
  late final GeneratedColumn<Uint8List> profileKey = GeneratedColumn<Uint8List>(
    'profile_key',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileVersionMeta = const VerificationMeta(
    'profileVersion',
  );
  @override
  late final GeneratedColumn<int> profileVersion = GeneratedColumn<int>(
    'profile_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> registeredAt =
      GeneratedColumn<int>(
        'registered_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SelfAccountTable.$converterregisteredAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    deviceId,
    serverDomain,
    helixName,
    phoneNumber,
    profileName,
    profileKey,
    profileVersion,
    registeredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'self_account';
  @override
  VerificationContext validateIntegrity(
    Insertable<SelfAccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('server_domain')) {
      context.handle(
        _serverDomainMeta,
        serverDomain.isAcceptableOrUnknown(
          data['server_domain']!,
          _serverDomainMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverDomainMeta);
    }
    if (data.containsKey('helix_name')) {
      context.handle(
        _helixNameMeta,
        helixName.isAcceptableOrUnknown(data['helix_name']!, _helixNameMeta),
      );
    }
    if (data.containsKey('phone_number')) {
      context.handle(
        _phoneNumberMeta,
        phoneNumber.isAcceptableOrUnknown(
          data['phone_number']!,
          _phoneNumberMeta,
        ),
      );
    }
    if (data.containsKey('profile_name')) {
      context.handle(
        _profileNameMeta,
        profileName.isAcceptableOrUnknown(
          data['profile_name']!,
          _profileNameMeta,
        ),
      );
    }
    if (data.containsKey('profile_key')) {
      context.handle(
        _profileKeyMeta,
        profileKey.isAcceptableOrUnknown(data['profile_key']!, _profileKeyMeta),
      );
    }
    if (data.containsKey('profile_version')) {
      context.handle(
        _profileVersionMeta,
        profileVersion.isAcceptableOrUnknown(
          data['profile_version']!,
          _profileVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SelfAccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SelfAccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      serverDomain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_domain'],
      )!,
      helixName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}helix_name'],
      ),
      phoneNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_number'],
      ),
      profileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_name'],
      ),
      profileKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}profile_key'],
      ),
      profileVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_version'],
      )!,
      registeredAt: $SelfAccountTable.$converterregisteredAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}registered_at'],
        )!,
      ),
    );
  }

  @override
  $SelfAccountTable createAlias(String alias) {
    return $SelfAccountTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterregisteredAt = const EpochMs();
}

class SelfAccountRow extends DataClass implements Insertable<SelfAccountRow> {
  final int id;
  final String accountId;
  final String deviceId;

  /// The home server's authority (`helix.example.org`), as in qualified
  /// addresses `uuid@domain`.
  final String serverDomain;
  final String? helixName;
  final String? phoneNumber;
  final String? profileName;
  final Uint8List? profileKey;
  final int profileVersion;
  final DateTime registeredAt;
  const SelfAccountRow({
    required this.id,
    required this.accountId,
    required this.deviceId,
    required this.serverDomain,
    this.helixName,
    this.phoneNumber,
    this.profileName,
    this.profileKey,
    required this.profileVersion,
    required this.registeredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<String>(accountId);
    map['device_id'] = Variable<String>(deviceId);
    map['server_domain'] = Variable<String>(serverDomain);
    if (!nullToAbsent || helixName != null) {
      map['helix_name'] = Variable<String>(helixName);
    }
    if (!nullToAbsent || phoneNumber != null) {
      map['phone_number'] = Variable<String>(phoneNumber);
    }
    if (!nullToAbsent || profileName != null) {
      map['profile_name'] = Variable<String>(profileName);
    }
    if (!nullToAbsent || profileKey != null) {
      map['profile_key'] = Variable<Uint8List>(profileKey);
    }
    map['profile_version'] = Variable<int>(profileVersion);
    {
      map['registered_at'] = Variable<int>(
        $SelfAccountTable.$converterregisteredAt.toSql(registeredAt),
      );
    }
    return map;
  }

  SelfAccountCompanion toCompanion(bool nullToAbsent) {
    return SelfAccountCompanion(
      id: Value(id),
      accountId: Value(accountId),
      deviceId: Value(deviceId),
      serverDomain: Value(serverDomain),
      helixName: helixName == null && nullToAbsent
          ? const Value.absent()
          : Value(helixName),
      phoneNumber: phoneNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(phoneNumber),
      profileName: profileName == null && nullToAbsent
          ? const Value.absent()
          : Value(profileName),
      profileKey: profileKey == null && nullToAbsent
          ? const Value.absent()
          : Value(profileKey),
      profileVersion: Value(profileVersion),
      registeredAt: Value(registeredAt),
    );
  }

  factory SelfAccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SelfAccountRow(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      serverDomain: serializer.fromJson<String>(json['serverDomain']),
      helixName: serializer.fromJson<String?>(json['helixName']),
      phoneNumber: serializer.fromJson<String?>(json['phoneNumber']),
      profileName: serializer.fromJson<String?>(json['profileName']),
      profileKey: serializer.fromJson<Uint8List?>(json['profileKey']),
      profileVersion: serializer.fromJson<int>(json['profileVersion']),
      registeredAt: serializer.fromJson<DateTime>(json['registeredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountId': serializer.toJson<String>(accountId),
      'deviceId': serializer.toJson<String>(deviceId),
      'serverDomain': serializer.toJson<String>(serverDomain),
      'helixName': serializer.toJson<String?>(helixName),
      'phoneNumber': serializer.toJson<String?>(phoneNumber),
      'profileName': serializer.toJson<String?>(profileName),
      'profileKey': serializer.toJson<Uint8List?>(profileKey),
      'profileVersion': serializer.toJson<int>(profileVersion),
      'registeredAt': serializer.toJson<DateTime>(registeredAt),
    };
  }

  SelfAccountRow copyWith({
    int? id,
    String? accountId,
    String? deviceId,
    String? serverDomain,
    Value<String?> helixName = const Value.absent(),
    Value<String?> phoneNumber = const Value.absent(),
    Value<String?> profileName = const Value.absent(),
    Value<Uint8List?> profileKey = const Value.absent(),
    int? profileVersion,
    DateTime? registeredAt,
  }) => SelfAccountRow(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    deviceId: deviceId ?? this.deviceId,
    serverDomain: serverDomain ?? this.serverDomain,
    helixName: helixName.present ? helixName.value : this.helixName,
    phoneNumber: phoneNumber.present ? phoneNumber.value : this.phoneNumber,
    profileName: profileName.present ? profileName.value : this.profileName,
    profileKey: profileKey.present ? profileKey.value : this.profileKey,
    profileVersion: profileVersion ?? this.profileVersion,
    registeredAt: registeredAt ?? this.registeredAt,
  );
  SelfAccountRow copyWithCompanion(SelfAccountCompanion data) {
    return SelfAccountRow(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      serverDomain: data.serverDomain.present
          ? data.serverDomain.value
          : this.serverDomain,
      helixName: data.helixName.present ? data.helixName.value : this.helixName,
      phoneNumber: data.phoneNumber.present
          ? data.phoneNumber.value
          : this.phoneNumber,
      profileName: data.profileName.present
          ? data.profileName.value
          : this.profileName,
      profileKey: data.profileKey.present
          ? data.profileKey.value
          : this.profileKey,
      profileVersion: data.profileVersion.present
          ? data.profileVersion.value
          : this.profileVersion,
      registeredAt: data.registeredAt.present
          ? data.registeredAt.value
          : this.registeredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SelfAccountRow(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverDomain: $serverDomain, ')
          ..write('helixName: $helixName, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('profileName: $profileName, ')
          ..write('profileKey: $profileKey, ')
          ..write('profileVersion: $profileVersion, ')
          ..write('registeredAt: $registeredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    deviceId,
    serverDomain,
    helixName,
    phoneNumber,
    profileName,
    $driftBlobEquality.hash(profileKey),
    profileVersion,
    registeredAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SelfAccountRow &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.deviceId == this.deviceId &&
          other.serverDomain == this.serverDomain &&
          other.helixName == this.helixName &&
          other.phoneNumber == this.phoneNumber &&
          other.profileName == this.profileName &&
          $driftBlobEquality.equals(other.profileKey, this.profileKey) &&
          other.profileVersion == this.profileVersion &&
          other.registeredAt == this.registeredAt);
}

class SelfAccountCompanion extends UpdateCompanion<SelfAccountRow> {
  final Value<int> id;
  final Value<String> accountId;
  final Value<String> deviceId;
  final Value<String> serverDomain;
  final Value<String?> helixName;
  final Value<String?> phoneNumber;
  final Value<String?> profileName;
  final Value<Uint8List?> profileKey;
  final Value<int> profileVersion;
  final Value<DateTime> registeredAt;
  const SelfAccountCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.serverDomain = const Value.absent(),
    this.helixName = const Value.absent(),
    this.phoneNumber = const Value.absent(),
    this.profileName = const Value.absent(),
    this.profileKey = const Value.absent(),
    this.profileVersion = const Value.absent(),
    this.registeredAt = const Value.absent(),
  });
  SelfAccountCompanion.insert({
    this.id = const Value.absent(),
    required String accountId,
    required String deviceId,
    required String serverDomain,
    this.helixName = const Value.absent(),
    this.phoneNumber = const Value.absent(),
    this.profileName = const Value.absent(),
    this.profileKey = const Value.absent(),
    this.profileVersion = const Value.absent(),
    required DateTime registeredAt,
  }) : accountId = Value(accountId),
       deviceId = Value(deviceId),
       serverDomain = Value(serverDomain),
       registeredAt = Value(registeredAt);
  static Insertable<SelfAccountRow> custom({
    Expression<int>? id,
    Expression<String>? accountId,
    Expression<String>? deviceId,
    Expression<String>? serverDomain,
    Expression<String>? helixName,
    Expression<String>? phoneNumber,
    Expression<String>? profileName,
    Expression<Uint8List>? profileKey,
    Expression<int>? profileVersion,
    Expression<int>? registeredAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (deviceId != null) 'device_id': deviceId,
      if (serverDomain != null) 'server_domain': serverDomain,
      if (helixName != null) 'helix_name': helixName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (profileName != null) 'profile_name': profileName,
      if (profileKey != null) 'profile_key': profileKey,
      if (profileVersion != null) 'profile_version': profileVersion,
      if (registeredAt != null) 'registered_at': registeredAt,
    });
  }

  SelfAccountCompanion copyWith({
    Value<int>? id,
    Value<String>? accountId,
    Value<String>? deviceId,
    Value<String>? serverDomain,
    Value<String?>? helixName,
    Value<String?>? phoneNumber,
    Value<String?>? profileName,
    Value<Uint8List?>? profileKey,
    Value<int>? profileVersion,
    Value<DateTime>? registeredAt,
  }) {
    return SelfAccountCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      deviceId: deviceId ?? this.deviceId,
      serverDomain: serverDomain ?? this.serverDomain,
      helixName: helixName ?? this.helixName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profileName: profileName ?? this.profileName,
      profileKey: profileKey ?? this.profileKey,
      profileVersion: profileVersion ?? this.profileVersion,
      registeredAt: registeredAt ?? this.registeredAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (serverDomain.present) {
      map['server_domain'] = Variable<String>(serverDomain.value);
    }
    if (helixName.present) {
      map['helix_name'] = Variable<String>(helixName.value);
    }
    if (phoneNumber.present) {
      map['phone_number'] = Variable<String>(phoneNumber.value);
    }
    if (profileName.present) {
      map['profile_name'] = Variable<String>(profileName.value);
    }
    if (profileKey.present) {
      map['profile_key'] = Variable<Uint8List>(profileKey.value);
    }
    if (profileVersion.present) {
      map['profile_version'] = Variable<int>(profileVersion.value);
    }
    if (registeredAt.present) {
      map['registered_at'] = Variable<int>(
        $SelfAccountTable.$converterregisteredAt.toSql(registeredAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SelfAccountCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('deviceId: $deviceId, ')
          ..write('serverDomain: $serverDomain, ')
          ..write('helixName: $helixName, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('profileName: $profileName, ')
          ..write('profileKey: $profileKey, ')
          ..write('profileVersion: $profileVersion, ')
          ..write('registeredAt: $registeredAt')
          ..write(')'))
        .toString();
  }
}

class $SelfDevicesTable extends SelfDevices
    with TableInfo<$SelfDevicesTable, SelfDeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SelfDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> linkedAt =
      GeneratedColumn<int>(
        'linked_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($SelfDevicesTable.$converterlinkedAtn);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastActiveAt =
      GeneratedColumn<int>(
        'last_active_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($SelfDevicesTable.$converterlastActiveAtn);
  static const VerificationMeta _isThisDeviceMeta = const VerificationMeta(
    'isThisDevice',
  );
  @override
  late final GeneratedColumn<bool> isThisDevice = GeneratedColumn<bool>(
    'is_this_device',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_this_device" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    name,
    platform,
    linkedAt,
    lastActiveAt,
    isThisDevice,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'self_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<SelfDeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    }
    if (data.containsKey('is_this_device')) {
      context.handle(
        _isThisDeviceMeta,
        isThisDevice.isAcceptableOrUnknown(
          data['is_this_device']!,
          _isThisDeviceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  SelfDeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SelfDeviceRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      ),
      linkedAt: $SelfDevicesTable.$converterlinkedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}linked_at'],
        ),
      ),
      lastActiveAt: $SelfDevicesTable.$converterlastActiveAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_active_at'],
        ),
      ),
      isThisDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_this_device'],
      )!,
    );
  }

  @override
  $SelfDevicesTable createAlias(String alias) {
    return $SelfDevicesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterlinkedAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterlinkedAtn =
      NullAwareTypeConverter.wrap($converterlinkedAt);
  static TypeConverter<DateTime, int> $converterlastActiveAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterlastActiveAtn =
      NullAwareTypeConverter.wrap($converterlastActiveAt);
}

class SelfDeviceRow extends DataClass implements Insertable<SelfDeviceRow> {
  final String deviceId;
  final String? name;
  final String? platform;
  final DateTime? linkedAt;
  final DateTime? lastActiveAt;
  final bool isThisDevice;
  const SelfDeviceRow({
    required this.deviceId,
    this.name,
    this.platform,
    this.linkedAt,
    this.lastActiveAt,
    required this.isThisDevice,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || platform != null) {
      map['platform'] = Variable<String>(platform);
    }
    if (!nullToAbsent || linkedAt != null) {
      map['linked_at'] = Variable<int>(
        $SelfDevicesTable.$converterlinkedAtn.toSql(linkedAt),
      );
    }
    if (!nullToAbsent || lastActiveAt != null) {
      map['last_active_at'] = Variable<int>(
        $SelfDevicesTable.$converterlastActiveAtn.toSql(lastActiveAt),
      );
    }
    map['is_this_device'] = Variable<bool>(isThisDevice);
    return map;
  }

  SelfDevicesCompanion toCompanion(bool nullToAbsent) {
    return SelfDevicesCompanion(
      deviceId: Value(deviceId),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      platform: platform == null && nullToAbsent
          ? const Value.absent()
          : Value(platform),
      linkedAt: linkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedAt),
      lastActiveAt: lastActiveAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastActiveAt),
      isThisDevice: Value(isThisDevice),
    );
  }

  factory SelfDeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SelfDeviceRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      name: serializer.fromJson<String?>(json['name']),
      platform: serializer.fromJson<String?>(json['platform']),
      linkedAt: serializer.fromJson<DateTime?>(json['linkedAt']),
      lastActiveAt: serializer.fromJson<DateTime?>(json['lastActiveAt']),
      isThisDevice: serializer.fromJson<bool>(json['isThisDevice']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'name': serializer.toJson<String?>(name),
      'platform': serializer.toJson<String?>(platform),
      'linkedAt': serializer.toJson<DateTime?>(linkedAt),
      'lastActiveAt': serializer.toJson<DateTime?>(lastActiveAt),
      'isThisDevice': serializer.toJson<bool>(isThisDevice),
    };
  }

  SelfDeviceRow copyWith({
    String? deviceId,
    Value<String?> name = const Value.absent(),
    Value<String?> platform = const Value.absent(),
    Value<DateTime?> linkedAt = const Value.absent(),
    Value<DateTime?> lastActiveAt = const Value.absent(),
    bool? isThisDevice,
  }) => SelfDeviceRow(
    deviceId: deviceId ?? this.deviceId,
    name: name.present ? name.value : this.name,
    platform: platform.present ? platform.value : this.platform,
    linkedAt: linkedAt.present ? linkedAt.value : this.linkedAt,
    lastActiveAt: lastActiveAt.present ? lastActiveAt.value : this.lastActiveAt,
    isThisDevice: isThisDevice ?? this.isThisDevice,
  );
  SelfDeviceRow copyWithCompanion(SelfDevicesCompanion data) {
    return SelfDeviceRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      name: data.name.present ? data.name.value : this.name,
      platform: data.platform.present ? data.platform.value : this.platform,
      linkedAt: data.linkedAt.present ? data.linkedAt.value : this.linkedAt,
      lastActiveAt: data.lastActiveAt.present
          ? data.lastActiveAt.value
          : this.lastActiveAt,
      isThisDevice: data.isThisDevice.present
          ? data.isThisDevice.value
          : this.isThisDevice,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SelfDeviceRow(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('linkedAt: $linkedAt, ')
          ..write('lastActiveAt: $lastActiveAt, ')
          ..write('isThisDevice: $isThisDevice')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    name,
    platform,
    linkedAt,
    lastActiveAt,
    isThisDevice,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SelfDeviceRow &&
          other.deviceId == this.deviceId &&
          other.name == this.name &&
          other.platform == this.platform &&
          other.linkedAt == this.linkedAt &&
          other.lastActiveAt == this.lastActiveAt &&
          other.isThisDevice == this.isThisDevice);
}

class SelfDevicesCompanion extends UpdateCompanion<SelfDeviceRow> {
  final Value<String> deviceId;
  final Value<String?> name;
  final Value<String?> platform;
  final Value<DateTime?> linkedAt;
  final Value<DateTime?> lastActiveAt;
  final Value<bool> isThisDevice;
  final Value<int> rowid;
  const SelfDevicesCompanion({
    this.deviceId = const Value.absent(),
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.linkedAt = const Value.absent(),
    this.lastActiveAt = const Value.absent(),
    this.isThisDevice = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SelfDevicesCompanion.insert({
    required String deviceId,
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.linkedAt = const Value.absent(),
    this.lastActiveAt = const Value.absent(),
    this.isThisDevice = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId);
  static Insertable<SelfDeviceRow> custom({
    Expression<String>? deviceId,
    Expression<String>? name,
    Expression<String>? platform,
    Expression<int>? linkedAt,
    Expression<int>? lastActiveAt,
    Expression<bool>? isThisDevice,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
      if (linkedAt != null) 'linked_at': linkedAt,
      if (lastActiveAt != null) 'last_active_at': lastActiveAt,
      if (isThisDevice != null) 'is_this_device': isThisDevice,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SelfDevicesCompanion copyWith({
    Value<String>? deviceId,
    Value<String?>? name,
    Value<String?>? platform,
    Value<DateTime?>? linkedAt,
    Value<DateTime?>? lastActiveAt,
    Value<bool>? isThisDevice,
    Value<int>? rowid,
  }) {
    return SelfDevicesCompanion(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      linkedAt: linkedAt ?? this.linkedAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      isThisDevice: isThisDevice ?? this.isThisDevice,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (linkedAt.present) {
      map['linked_at'] = Variable<int>(
        $SelfDevicesTable.$converterlinkedAtn.toSql(linkedAt.value),
      );
    }
    if (lastActiveAt.present) {
      map['last_active_at'] = Variable<int>(
        $SelfDevicesTable.$converterlastActiveAtn.toSql(lastActiveAt.value),
      );
    }
    if (isThisDevice.present) {
      map['is_this_device'] = Variable<bool>(isThisDevice.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SelfDevicesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('linkedAt: $linkedAt, ')
          ..write('lastActiveAt: $lastActiveAt, ')
          ..write('isThisDevice: $isThisDevice, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeopleTable extends People with TableInfo<$PeopleTable, PersonRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeopleTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _helixNameMeta = const VerificationMeta(
    'helixName',
  );
  @override
  late final GeneratedColumn<String> helixName = GeneratedColumn<String>(
    'helix_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneNumberMeta = const VerificationMeta(
    'phoneNumber',
  );
  @override
  late final GeneratedColumn<String> phoneNumber = GeneratedColumn<String>(
    'phone_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneHashMeta = const VerificationMeta(
    'phoneHash',
  );
  @override
  late final GeneratedColumn<String> phoneHash = GeneratedColumn<String>(
    'phone_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phonebookNameMeta = const VerificationMeta(
    'phonebookName',
  );
  @override
  late final GeneratedColumn<String> phonebookName = GeneratedColumn<String>(
    'phonebook_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileNameMeta = const VerificationMeta(
    'profileName',
  );
  @override
  late final GeneratedColumn<String> profileName = GeneratedColumn<String>(
    'profile_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileKeyMeta = const VerificationMeta(
    'profileKey',
  );
  @override
  late final GeneratedColumn<Uint8List> profileKey = GeneratedColumn<Uint8List>(
    'profile_key',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileVersionMeta = const VerificationMeta(
    'profileVersion',
  );
  @override
  late final GeneratedColumn<int> profileVersion = GeneratedColumn<int>(
    'profile_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarBlobMeta = const VerificationMeta(
    'avatarBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> avatarBlob = GeneratedColumn<Uint8List>(
    'avatar_blob',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<Uint8List> identityKey =
      GeneratedColumn<Uint8List>(
        'identity_key',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _identityVerifiedMeta = const VerificationMeta(
    'identityVerified',
  );
  @override
  late final GeneratedColumn<bool> identityVerified = GeneratedColumn<bool>(
    'identity_verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("identity_verified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int>
  identityChangedAt = GeneratedColumn<int>(
    'identity_changed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  ).withConverter<DateTime?>($PeopleTable.$converteridentityChangedAtn);
  static const VerificationMeta _blockedMeta = const VerificationMeta(
    'blocked',
  );
  @override
  late final GeneratedColumn<bool> blocked = GeneratedColumn<bool>(
    'blocked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("blocked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PeopleTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    helixName,
    phoneNumber,
    phoneHash,
    phonebookName,
    nickname,
    profileName,
    profileKey,
    profileVersion,
    avatarBlob,
    identityKey,
    identityVerified,
    identityChangedAt,
    blocked,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'people';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('helix_name')) {
      context.handle(
        _helixNameMeta,
        helixName.isAcceptableOrUnknown(data['helix_name']!, _helixNameMeta),
      );
    }
    if (data.containsKey('phone_number')) {
      context.handle(
        _phoneNumberMeta,
        phoneNumber.isAcceptableOrUnknown(
          data['phone_number']!,
          _phoneNumberMeta,
        ),
      );
    }
    if (data.containsKey('phone_hash')) {
      context.handle(
        _phoneHashMeta,
        phoneHash.isAcceptableOrUnknown(data['phone_hash']!, _phoneHashMeta),
      );
    }
    if (data.containsKey('phonebook_name')) {
      context.handle(
        _phonebookNameMeta,
        phonebookName.isAcceptableOrUnknown(
          data['phonebook_name']!,
          _phonebookNameMeta,
        ),
      );
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    if (data.containsKey('profile_name')) {
      context.handle(
        _profileNameMeta,
        profileName.isAcceptableOrUnknown(
          data['profile_name']!,
          _profileNameMeta,
        ),
      );
    }
    if (data.containsKey('profile_key')) {
      context.handle(
        _profileKeyMeta,
        profileKey.isAcceptableOrUnknown(data['profile_key']!, _profileKeyMeta),
      );
    }
    if (data.containsKey('profile_version')) {
      context.handle(
        _profileVersionMeta,
        profileVersion.isAcceptableOrUnknown(
          data['profile_version']!,
          _profileVersionMeta,
        ),
      );
    }
    if (data.containsKey('avatar_blob')) {
      context.handle(
        _avatarBlobMeta,
        avatarBlob.isAcceptableOrUnknown(data['avatar_blob']!, _avatarBlobMeta),
      );
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    }
    if (data.containsKey('identity_verified')) {
      context.handle(
        _identityVerifiedMeta,
        identityVerified.isAcceptableOrUnknown(
          data['identity_verified']!,
          _identityVerifiedMeta,
        ),
      );
    }
    if (data.containsKey('blocked')) {
      context.handle(
        _blockedMeta,
        blocked.isAcceptableOrUnknown(data['blocked']!, _blockedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId};
  @override
  PersonRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      helixName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}helix_name'],
      ),
      phoneNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_number'],
      ),
      phoneHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_hash'],
      ),
      phonebookName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phonebook_name'],
      ),
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      ),
      profileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_name'],
      ),
      profileKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}profile_key'],
      ),
      profileVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_version'],
      ),
      avatarBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}avatar_blob'],
      ),
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}identity_key'],
      ),
      identityVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}identity_verified'],
      )!,
      identityChangedAt: $PeopleTable.$converteridentityChangedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}identity_changed_at'],
        ),
      ),
      blocked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}blocked'],
      )!,
      updatedAt: $PeopleTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $PeopleTable createAlias(String alias) {
    return $PeopleTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converteridentityChangedAt =
      const EpochMs();
  static TypeConverter<DateTime?, int?> $converteridentityChangedAtn =
      NullAwareTypeConverter.wrap($converteridentityChangedAt);
  static TypeConverter<DateTime, int> $converterupdatedAt = const EpochMs();
}

class PersonRow extends DataClass implements Insertable<PersonRow> {
  /// Bare uuid for the home server, `uuid@domain` for other servers.
  final String accountId;
  final String? helixName;
  final String? phoneNumber;
  final String? phoneHash;
  final String? phonebookName;
  final String? nickname;

  /// From the decrypted profile (CRYPTO_V2.md §9).
  final String? profileName;
  final Uint8List? profileKey;
  final int? profileVersion;
  final Uint8List? avatarBlob;

  /// The pinned account identity key (AIK, trust on first use).
  final Uint8List? identityKey;

  /// The user compared safety numbers; reset on a key change.
  final bool identityVerified;
  final DateTime? identityChangedAt;
  final bool blocked;
  final DateTime updatedAt;
  const PersonRow({
    required this.accountId,
    this.helixName,
    this.phoneNumber,
    this.phoneHash,
    this.phonebookName,
    this.nickname,
    this.profileName,
    this.profileKey,
    this.profileVersion,
    this.avatarBlob,
    this.identityKey,
    required this.identityVerified,
    this.identityChangedAt,
    required this.blocked,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || helixName != null) {
      map['helix_name'] = Variable<String>(helixName);
    }
    if (!nullToAbsent || phoneNumber != null) {
      map['phone_number'] = Variable<String>(phoneNumber);
    }
    if (!nullToAbsent || phoneHash != null) {
      map['phone_hash'] = Variable<String>(phoneHash);
    }
    if (!nullToAbsent || phonebookName != null) {
      map['phonebook_name'] = Variable<String>(phonebookName);
    }
    if (!nullToAbsent || nickname != null) {
      map['nickname'] = Variable<String>(nickname);
    }
    if (!nullToAbsent || profileName != null) {
      map['profile_name'] = Variable<String>(profileName);
    }
    if (!nullToAbsent || profileKey != null) {
      map['profile_key'] = Variable<Uint8List>(profileKey);
    }
    if (!nullToAbsent || profileVersion != null) {
      map['profile_version'] = Variable<int>(profileVersion);
    }
    if (!nullToAbsent || avatarBlob != null) {
      map['avatar_blob'] = Variable<Uint8List>(avatarBlob);
    }
    if (!nullToAbsent || identityKey != null) {
      map['identity_key'] = Variable<Uint8List>(identityKey);
    }
    map['identity_verified'] = Variable<bool>(identityVerified);
    if (!nullToAbsent || identityChangedAt != null) {
      map['identity_changed_at'] = Variable<int>(
        $PeopleTable.$converteridentityChangedAtn.toSql(identityChangedAt),
      );
    }
    map['blocked'] = Variable<bool>(blocked);
    {
      map['updated_at'] = Variable<int>(
        $PeopleTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  PeopleCompanion toCompanion(bool nullToAbsent) {
    return PeopleCompanion(
      accountId: Value(accountId),
      helixName: helixName == null && nullToAbsent
          ? const Value.absent()
          : Value(helixName),
      phoneNumber: phoneNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(phoneNumber),
      phoneHash: phoneHash == null && nullToAbsent
          ? const Value.absent()
          : Value(phoneHash),
      phonebookName: phonebookName == null && nullToAbsent
          ? const Value.absent()
          : Value(phonebookName),
      nickname: nickname == null && nullToAbsent
          ? const Value.absent()
          : Value(nickname),
      profileName: profileName == null && nullToAbsent
          ? const Value.absent()
          : Value(profileName),
      profileKey: profileKey == null && nullToAbsent
          ? const Value.absent()
          : Value(profileKey),
      profileVersion: profileVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(profileVersion),
      avatarBlob: avatarBlob == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarBlob),
      identityKey: identityKey == null && nullToAbsent
          ? const Value.absent()
          : Value(identityKey),
      identityVerified: Value(identityVerified),
      identityChangedAt: identityChangedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(identityChangedAt),
      blocked: Value(blocked),
      updatedAt: Value(updatedAt),
    );
  }

  factory PersonRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      helixName: serializer.fromJson<String?>(json['helixName']),
      phoneNumber: serializer.fromJson<String?>(json['phoneNumber']),
      phoneHash: serializer.fromJson<String?>(json['phoneHash']),
      phonebookName: serializer.fromJson<String?>(json['phonebookName']),
      nickname: serializer.fromJson<String?>(json['nickname']),
      profileName: serializer.fromJson<String?>(json['profileName']),
      profileKey: serializer.fromJson<Uint8List?>(json['profileKey']),
      profileVersion: serializer.fromJson<int?>(json['profileVersion']),
      avatarBlob: serializer.fromJson<Uint8List?>(json['avatarBlob']),
      identityKey: serializer.fromJson<Uint8List?>(json['identityKey']),
      identityVerified: serializer.fromJson<bool>(json['identityVerified']),
      identityChangedAt: serializer.fromJson<DateTime?>(
        json['identityChangedAt'],
      ),
      blocked: serializer.fromJson<bool>(json['blocked']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'helixName': serializer.toJson<String?>(helixName),
      'phoneNumber': serializer.toJson<String?>(phoneNumber),
      'phoneHash': serializer.toJson<String?>(phoneHash),
      'phonebookName': serializer.toJson<String?>(phonebookName),
      'nickname': serializer.toJson<String?>(nickname),
      'profileName': serializer.toJson<String?>(profileName),
      'profileKey': serializer.toJson<Uint8List?>(profileKey),
      'profileVersion': serializer.toJson<int?>(profileVersion),
      'avatarBlob': serializer.toJson<Uint8List?>(avatarBlob),
      'identityKey': serializer.toJson<Uint8List?>(identityKey),
      'identityVerified': serializer.toJson<bool>(identityVerified),
      'identityChangedAt': serializer.toJson<DateTime?>(identityChangedAt),
      'blocked': serializer.toJson<bool>(blocked),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PersonRow copyWith({
    String? accountId,
    Value<String?> helixName = const Value.absent(),
    Value<String?> phoneNumber = const Value.absent(),
    Value<String?> phoneHash = const Value.absent(),
    Value<String?> phonebookName = const Value.absent(),
    Value<String?> nickname = const Value.absent(),
    Value<String?> profileName = const Value.absent(),
    Value<Uint8List?> profileKey = const Value.absent(),
    Value<int?> profileVersion = const Value.absent(),
    Value<Uint8List?> avatarBlob = const Value.absent(),
    Value<Uint8List?> identityKey = const Value.absent(),
    bool? identityVerified,
    Value<DateTime?> identityChangedAt = const Value.absent(),
    bool? blocked,
    DateTime? updatedAt,
  }) => PersonRow(
    accountId: accountId ?? this.accountId,
    helixName: helixName.present ? helixName.value : this.helixName,
    phoneNumber: phoneNumber.present ? phoneNumber.value : this.phoneNumber,
    phoneHash: phoneHash.present ? phoneHash.value : this.phoneHash,
    phonebookName: phonebookName.present
        ? phonebookName.value
        : this.phonebookName,
    nickname: nickname.present ? nickname.value : this.nickname,
    profileName: profileName.present ? profileName.value : this.profileName,
    profileKey: profileKey.present ? profileKey.value : this.profileKey,
    profileVersion: profileVersion.present
        ? profileVersion.value
        : this.profileVersion,
    avatarBlob: avatarBlob.present ? avatarBlob.value : this.avatarBlob,
    identityKey: identityKey.present ? identityKey.value : this.identityKey,
    identityVerified: identityVerified ?? this.identityVerified,
    identityChangedAt: identityChangedAt.present
        ? identityChangedAt.value
        : this.identityChangedAt,
    blocked: blocked ?? this.blocked,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PersonRow copyWithCompanion(PeopleCompanion data) {
    return PersonRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      helixName: data.helixName.present ? data.helixName.value : this.helixName,
      phoneNumber: data.phoneNumber.present
          ? data.phoneNumber.value
          : this.phoneNumber,
      phoneHash: data.phoneHash.present ? data.phoneHash.value : this.phoneHash,
      phonebookName: data.phonebookName.present
          ? data.phonebookName.value
          : this.phonebookName,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      profileName: data.profileName.present
          ? data.profileName.value
          : this.profileName,
      profileKey: data.profileKey.present
          ? data.profileKey.value
          : this.profileKey,
      profileVersion: data.profileVersion.present
          ? data.profileVersion.value
          : this.profileVersion,
      avatarBlob: data.avatarBlob.present
          ? data.avatarBlob.value
          : this.avatarBlob,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      identityVerified: data.identityVerified.present
          ? data.identityVerified.value
          : this.identityVerified,
      identityChangedAt: data.identityChangedAt.present
          ? data.identityChangedAt.value
          : this.identityChangedAt,
      blocked: data.blocked.present ? data.blocked.value : this.blocked,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonRow(')
          ..write('accountId: $accountId, ')
          ..write('helixName: $helixName, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('phoneHash: $phoneHash, ')
          ..write('phonebookName: $phonebookName, ')
          ..write('nickname: $nickname, ')
          ..write('profileName: $profileName, ')
          ..write('profileKey: $profileKey, ')
          ..write('profileVersion: $profileVersion, ')
          ..write('avatarBlob: $avatarBlob, ')
          ..write('identityKey: $identityKey, ')
          ..write('identityVerified: $identityVerified, ')
          ..write('identityChangedAt: $identityChangedAt, ')
          ..write('blocked: $blocked, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    helixName,
    phoneNumber,
    phoneHash,
    phonebookName,
    nickname,
    profileName,
    $driftBlobEquality.hash(profileKey),
    profileVersion,
    $driftBlobEquality.hash(avatarBlob),
    $driftBlobEquality.hash(identityKey),
    identityVerified,
    identityChangedAt,
    blocked,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonRow &&
          other.accountId == this.accountId &&
          other.helixName == this.helixName &&
          other.phoneNumber == this.phoneNumber &&
          other.phoneHash == this.phoneHash &&
          other.phonebookName == this.phonebookName &&
          other.nickname == this.nickname &&
          other.profileName == this.profileName &&
          $driftBlobEquality.equals(other.profileKey, this.profileKey) &&
          other.profileVersion == this.profileVersion &&
          $driftBlobEquality.equals(other.avatarBlob, this.avatarBlob) &&
          $driftBlobEquality.equals(other.identityKey, this.identityKey) &&
          other.identityVerified == this.identityVerified &&
          other.identityChangedAt == this.identityChangedAt &&
          other.blocked == this.blocked &&
          other.updatedAt == this.updatedAt);
}

class PeopleCompanion extends UpdateCompanion<PersonRow> {
  final Value<String> accountId;
  final Value<String?> helixName;
  final Value<String?> phoneNumber;
  final Value<String?> phoneHash;
  final Value<String?> phonebookName;
  final Value<String?> nickname;
  final Value<String?> profileName;
  final Value<Uint8List?> profileKey;
  final Value<int?> profileVersion;
  final Value<Uint8List?> avatarBlob;
  final Value<Uint8List?> identityKey;
  final Value<bool> identityVerified;
  final Value<DateTime?> identityChangedAt;
  final Value<bool> blocked;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PeopleCompanion({
    this.accountId = const Value.absent(),
    this.helixName = const Value.absent(),
    this.phoneNumber = const Value.absent(),
    this.phoneHash = const Value.absent(),
    this.phonebookName = const Value.absent(),
    this.nickname = const Value.absent(),
    this.profileName = const Value.absent(),
    this.profileKey = const Value.absent(),
    this.profileVersion = const Value.absent(),
    this.avatarBlob = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.identityVerified = const Value.absent(),
    this.identityChangedAt = const Value.absent(),
    this.blocked = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeopleCompanion.insert({
    required String accountId,
    this.helixName = const Value.absent(),
    this.phoneNumber = const Value.absent(),
    this.phoneHash = const Value.absent(),
    this.phonebookName = const Value.absent(),
    this.nickname = const Value.absent(),
    this.profileName = const Value.absent(),
    this.profileKey = const Value.absent(),
    this.profileVersion = const Value.absent(),
    this.avatarBlob = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.identityVerified = const Value.absent(),
    this.identityChangedAt = const Value.absent(),
    this.blocked = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       updatedAt = Value(updatedAt);
  static Insertable<PersonRow> custom({
    Expression<String>? accountId,
    Expression<String>? helixName,
    Expression<String>? phoneNumber,
    Expression<String>? phoneHash,
    Expression<String>? phonebookName,
    Expression<String>? nickname,
    Expression<String>? profileName,
    Expression<Uint8List>? profileKey,
    Expression<int>? profileVersion,
    Expression<Uint8List>? avatarBlob,
    Expression<Uint8List>? identityKey,
    Expression<bool>? identityVerified,
    Expression<int>? identityChangedAt,
    Expression<bool>? blocked,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (helixName != null) 'helix_name': helixName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (phoneHash != null) 'phone_hash': phoneHash,
      if (phonebookName != null) 'phonebook_name': phonebookName,
      if (nickname != null) 'nickname': nickname,
      if (profileName != null) 'profile_name': profileName,
      if (profileKey != null) 'profile_key': profileKey,
      if (profileVersion != null) 'profile_version': profileVersion,
      if (avatarBlob != null) 'avatar_blob': avatarBlob,
      if (identityKey != null) 'identity_key': identityKey,
      if (identityVerified != null) 'identity_verified': identityVerified,
      if (identityChangedAt != null) 'identity_changed_at': identityChangedAt,
      if (blocked != null) 'blocked': blocked,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeopleCompanion copyWith({
    Value<String>? accountId,
    Value<String?>? helixName,
    Value<String?>? phoneNumber,
    Value<String?>? phoneHash,
    Value<String?>? phonebookName,
    Value<String?>? nickname,
    Value<String?>? profileName,
    Value<Uint8List?>? profileKey,
    Value<int?>? profileVersion,
    Value<Uint8List?>? avatarBlob,
    Value<Uint8List?>? identityKey,
    Value<bool>? identityVerified,
    Value<DateTime?>? identityChangedAt,
    Value<bool>? blocked,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PeopleCompanion(
      accountId: accountId ?? this.accountId,
      helixName: helixName ?? this.helixName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneHash: phoneHash ?? this.phoneHash,
      phonebookName: phonebookName ?? this.phonebookName,
      nickname: nickname ?? this.nickname,
      profileName: profileName ?? this.profileName,
      profileKey: profileKey ?? this.profileKey,
      profileVersion: profileVersion ?? this.profileVersion,
      avatarBlob: avatarBlob ?? this.avatarBlob,
      identityKey: identityKey ?? this.identityKey,
      identityVerified: identityVerified ?? this.identityVerified,
      identityChangedAt: identityChangedAt ?? this.identityChangedAt,
      blocked: blocked ?? this.blocked,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (helixName.present) {
      map['helix_name'] = Variable<String>(helixName.value);
    }
    if (phoneNumber.present) {
      map['phone_number'] = Variable<String>(phoneNumber.value);
    }
    if (phoneHash.present) {
      map['phone_hash'] = Variable<String>(phoneHash.value);
    }
    if (phonebookName.present) {
      map['phonebook_name'] = Variable<String>(phonebookName.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (profileName.present) {
      map['profile_name'] = Variable<String>(profileName.value);
    }
    if (profileKey.present) {
      map['profile_key'] = Variable<Uint8List>(profileKey.value);
    }
    if (profileVersion.present) {
      map['profile_version'] = Variable<int>(profileVersion.value);
    }
    if (avatarBlob.present) {
      map['avatar_blob'] = Variable<Uint8List>(avatarBlob.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<Uint8List>(identityKey.value);
    }
    if (identityVerified.present) {
      map['identity_verified'] = Variable<bool>(identityVerified.value);
    }
    if (identityChangedAt.present) {
      map['identity_changed_at'] = Variable<int>(
        $PeopleTable.$converteridentityChangedAtn.toSql(
          identityChangedAt.value,
        ),
      );
    }
    if (blocked.present) {
      map['blocked'] = Variable<bool>(blocked.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $PeopleTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeopleCompanion(')
          ..write('accountId: $accountId, ')
          ..write('helixName: $helixName, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('phoneHash: $phoneHash, ')
          ..write('phonebookName: $phonebookName, ')
          ..write('nickname: $nickname, ')
          ..write('profileName: $profileName, ')
          ..write('profileKey: $profileKey, ')
          ..write('profileVersion: $profileVersion, ')
          ..write('avatarBlob: $avatarBlob, ')
          ..write('identityKey: $identityKey, ')
          ..write('identityVerified: $identityVerified, ')
          ..write('identityChangedAt: $identityChangedAt, ')
          ..write('blocked: $blocked, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PersonDevicesTable extends PersonDevices
    with TableInfo<$PersonDevicesTable, PersonDeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<Uint8List> identityKey =
      GeneratedColumn<Uint8List>(
        'identity_key',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _signingKeyMeta = const VerificationMeta(
    'signingKey',
  );
  @override
  late final GeneratedColumn<Uint8List> signingKey = GeneratedColumn<Uint8List>(
    'signing_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _certificateMeta = const VerificationMeta(
    'certificate',
  );
  @override
  late final GeneratedColumn<Uint8List> certificate =
      GeneratedColumn<Uint8List>(
        'certificate',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DeviceTrust, String> trust =
      GeneratedColumn<String>(
        'trust',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DeviceTrust>($PersonDevicesTable.$convertertrust);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> firstSeenAt =
      GeneratedColumn<int>(
        'first_seen_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PersonDevicesTable.$converterfirstSeenAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PersonDevicesTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    deviceId,
    identityKey,
    signingKey,
    certificate,
    trust,
    firstSeenAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'person_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonDeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('signing_key')) {
      context.handle(
        _signingKeyMeta,
        signingKey.isAcceptableOrUnknown(data['signing_key']!, _signingKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_signingKeyMeta);
    }
    if (data.containsKey('certificate')) {
      context.handle(
        _certificateMeta,
        certificate.isAcceptableOrUnknown(
          data['certificate']!,
          _certificateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, deviceId};
  @override
  PersonDeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonDeviceRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}identity_key'],
      )!,
      signingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}signing_key'],
      )!,
      certificate: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}certificate'],
      ),
      trust: $PersonDevicesTable.$convertertrust.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}trust'],
        )!,
      ),
      firstSeenAt: $PersonDevicesTable.$converterfirstSeenAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}first_seen_at'],
        )!,
      ),
      updatedAt: $PersonDevicesTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $PersonDevicesTable createAlias(String alias) {
    return $PersonDevicesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DeviceTrust, String, String> $convertertrust =
      const EnumNameConverter<DeviceTrust>(DeviceTrust.values);
  static TypeConverter<DateTime, int> $converterfirstSeenAt = const EpochMs();
  static TypeConverter<DateTime, int> $converterupdatedAt = const EpochMs();
}

class PersonDeviceRow extends DataClass implements Insertable<PersonDeviceRow> {
  final String accountId;
  final String deviceId;

  /// Device identity key (DIK, X25519 public).
  final Uint8List identityKey;

  /// Device signing key (DSK, Ed25519 public).
  final Uint8List signingKey;
  final Uint8List? certificate;
  final DeviceTrust trust;
  final DateTime firstSeenAt;
  final DateTime updatedAt;
  const PersonDeviceRow({
    required this.accountId,
    required this.deviceId,
    required this.identityKey,
    required this.signingKey,
    this.certificate,
    required this.trust,
    required this.firstSeenAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['device_id'] = Variable<String>(deviceId);
    map['identity_key'] = Variable<Uint8List>(identityKey);
    map['signing_key'] = Variable<Uint8List>(signingKey);
    if (!nullToAbsent || certificate != null) {
      map['certificate'] = Variable<Uint8List>(certificate);
    }
    {
      map['trust'] = Variable<String>(
        $PersonDevicesTable.$convertertrust.toSql(trust),
      );
    }
    {
      map['first_seen_at'] = Variable<int>(
        $PersonDevicesTable.$converterfirstSeenAt.toSql(firstSeenAt),
      );
    }
    {
      map['updated_at'] = Variable<int>(
        $PersonDevicesTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  PersonDevicesCompanion toCompanion(bool nullToAbsent) {
    return PersonDevicesCompanion(
      accountId: Value(accountId),
      deviceId: Value(deviceId),
      identityKey: Value(identityKey),
      signingKey: Value(signingKey),
      certificate: certificate == null && nullToAbsent
          ? const Value.absent()
          : Value(certificate),
      trust: Value(trust),
      firstSeenAt: Value(firstSeenAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PersonDeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonDeviceRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      identityKey: serializer.fromJson<Uint8List>(json['identityKey']),
      signingKey: serializer.fromJson<Uint8List>(json['signingKey']),
      certificate: serializer.fromJson<Uint8List?>(json['certificate']),
      trust: $PersonDevicesTable.$convertertrust.fromJson(
        serializer.fromJson<String>(json['trust']),
      ),
      firstSeenAt: serializer.fromJson<DateTime>(json['firstSeenAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'deviceId': serializer.toJson<String>(deviceId),
      'identityKey': serializer.toJson<Uint8List>(identityKey),
      'signingKey': serializer.toJson<Uint8List>(signingKey),
      'certificate': serializer.toJson<Uint8List?>(certificate),
      'trust': serializer.toJson<String>(
        $PersonDevicesTable.$convertertrust.toJson(trust),
      ),
      'firstSeenAt': serializer.toJson<DateTime>(firstSeenAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PersonDeviceRow copyWith({
    String? accountId,
    String? deviceId,
    Uint8List? identityKey,
    Uint8List? signingKey,
    Value<Uint8List?> certificate = const Value.absent(),
    DeviceTrust? trust,
    DateTime? firstSeenAt,
    DateTime? updatedAt,
  }) => PersonDeviceRow(
    accountId: accountId ?? this.accountId,
    deviceId: deviceId ?? this.deviceId,
    identityKey: identityKey ?? this.identityKey,
    signingKey: signingKey ?? this.signingKey,
    certificate: certificate.present ? certificate.value : this.certificate,
    trust: trust ?? this.trust,
    firstSeenAt: firstSeenAt ?? this.firstSeenAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PersonDeviceRow copyWithCompanion(PersonDevicesCompanion data) {
    return PersonDeviceRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      signingKey: data.signingKey.present
          ? data.signingKey.value
          : this.signingKey,
      certificate: data.certificate.present
          ? data.certificate.value
          : this.certificate,
      trust: data.trust.present ? data.trust.value : this.trust,
      firstSeenAt: data.firstSeenAt.present
          ? data.firstSeenAt.value
          : this.firstSeenAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonDeviceRow(')
          ..write('accountId: $accountId, ')
          ..write('deviceId: $deviceId, ')
          ..write('identityKey: $identityKey, ')
          ..write('signingKey: $signingKey, ')
          ..write('certificate: $certificate, ')
          ..write('trust: $trust, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    deviceId,
    $driftBlobEquality.hash(identityKey),
    $driftBlobEquality.hash(signingKey),
    $driftBlobEquality.hash(certificate),
    trust,
    firstSeenAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonDeviceRow &&
          other.accountId == this.accountId &&
          other.deviceId == this.deviceId &&
          $driftBlobEquality.equals(other.identityKey, this.identityKey) &&
          $driftBlobEquality.equals(other.signingKey, this.signingKey) &&
          $driftBlobEquality.equals(other.certificate, this.certificate) &&
          other.trust == this.trust &&
          other.firstSeenAt == this.firstSeenAt &&
          other.updatedAt == this.updatedAt);
}

class PersonDevicesCompanion extends UpdateCompanion<PersonDeviceRow> {
  final Value<String> accountId;
  final Value<String> deviceId;
  final Value<Uint8List> identityKey;
  final Value<Uint8List> signingKey;
  final Value<Uint8List?> certificate;
  final Value<DeviceTrust> trust;
  final Value<DateTime> firstSeenAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PersonDevicesCompanion({
    this.accountId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.signingKey = const Value.absent(),
    this.certificate = const Value.absent(),
    this.trust = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PersonDevicesCompanion.insert({
    required String accountId,
    required String deviceId,
    required Uint8List identityKey,
    required Uint8List signingKey,
    this.certificate = const Value.absent(),
    required DeviceTrust trust,
    required DateTime firstSeenAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       deviceId = Value(deviceId),
       identityKey = Value(identityKey),
       signingKey = Value(signingKey),
       trust = Value(trust),
       firstSeenAt = Value(firstSeenAt),
       updatedAt = Value(updatedAt);
  static Insertable<PersonDeviceRow> custom({
    Expression<String>? accountId,
    Expression<String>? deviceId,
    Expression<Uint8List>? identityKey,
    Expression<Uint8List>? signingKey,
    Expression<Uint8List>? certificate,
    Expression<String>? trust,
    Expression<int>? firstSeenAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (deviceId != null) 'device_id': deviceId,
      if (identityKey != null) 'identity_key': identityKey,
      if (signingKey != null) 'signing_key': signingKey,
      if (certificate != null) 'certificate': certificate,
      if (trust != null) 'trust': trust,
      if (firstSeenAt != null) 'first_seen_at': firstSeenAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PersonDevicesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? deviceId,
    Value<Uint8List>? identityKey,
    Value<Uint8List>? signingKey,
    Value<Uint8List?>? certificate,
    Value<DeviceTrust>? trust,
    Value<DateTime>? firstSeenAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PersonDevicesCompanion(
      accountId: accountId ?? this.accountId,
      deviceId: deviceId ?? this.deviceId,
      identityKey: identityKey ?? this.identityKey,
      signingKey: signingKey ?? this.signingKey,
      certificate: certificate ?? this.certificate,
      trust: trust ?? this.trust,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<Uint8List>(identityKey.value);
    }
    if (signingKey.present) {
      map['signing_key'] = Variable<Uint8List>(signingKey.value);
    }
    if (certificate.present) {
      map['certificate'] = Variable<Uint8List>(certificate.value);
    }
    if (trust.present) {
      map['trust'] = Variable<String>(
        $PersonDevicesTable.$convertertrust.toSql(trust.value),
      );
    }
    if (firstSeenAt.present) {
      map['first_seen_at'] = Variable<int>(
        $PersonDevicesTable.$converterfirstSeenAt.toSql(firstSeenAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $PersonDevicesTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonDevicesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('deviceId: $deviceId, ')
          ..write('identityKey: $identityKey, ')
          ..write('signingKey: $signingKey, ')
          ..write('certificate: $certificate, ')
          ..write('trust: $trust, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IdentityTable extends Identity
    with TableInfo<$IdentityTable, IdentityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentityTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aikPublicMeta = const VerificationMeta(
    'aikPublic',
  );
  @override
  late final GeneratedColumn<Uint8List> aikPublic = GeneratedColumn<Uint8List>(
    'aik_public',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aikPrivateMeta = const VerificationMeta(
    'aikPrivate',
  );
  @override
  late final GeneratedColumn<Uint8List> aikPrivate = GeneratedColumn<Uint8List>(
    'aik_private',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dikPublicMeta = const VerificationMeta(
    'dikPublic',
  );
  @override
  late final GeneratedColumn<Uint8List> dikPublic = GeneratedColumn<Uint8List>(
    'dik_public',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dikPrivateMeta = const VerificationMeta(
    'dikPrivate',
  );
  @override
  late final GeneratedColumn<Uint8List> dikPrivate = GeneratedColumn<Uint8List>(
    'dik_private',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dskPublicMeta = const VerificationMeta(
    'dskPublic',
  );
  @override
  late final GeneratedColumn<Uint8List> dskPublic = GeneratedColumn<Uint8List>(
    'dsk_public',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dskPrivateMeta = const VerificationMeta(
    'dskPrivate',
  );
  @override
  late final GeneratedColumn<Uint8List> dskPrivate = GeneratedColumn<Uint8List>(
    'dsk_private',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceCertificateMeta = const VerificationMeta(
    'deviceCertificate',
  );
  @override
  late final GeneratedColumn<Uint8List> deviceCertificate =
      GeneratedColumn<Uint8List>(
        'device_certificate',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($IdentityTable.$convertercreatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    deviceId,
    aikPublic,
    aikPrivate,
    dikPublic,
    dikPrivate,
    dskPublic,
    dskPrivate,
    deviceCertificate,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identity';
  @override
  VerificationContext validateIntegrity(
    Insertable<IdentityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('aik_public')) {
      context.handle(
        _aikPublicMeta,
        aikPublic.isAcceptableOrUnknown(data['aik_public']!, _aikPublicMeta),
      );
    } else if (isInserting) {
      context.missing(_aikPublicMeta);
    }
    if (data.containsKey('aik_private')) {
      context.handle(
        _aikPrivateMeta,
        aikPrivate.isAcceptableOrUnknown(data['aik_private']!, _aikPrivateMeta),
      );
    } else if (isInserting) {
      context.missing(_aikPrivateMeta);
    }
    if (data.containsKey('dik_public')) {
      context.handle(
        _dikPublicMeta,
        dikPublic.isAcceptableOrUnknown(data['dik_public']!, _dikPublicMeta),
      );
    } else if (isInserting) {
      context.missing(_dikPublicMeta);
    }
    if (data.containsKey('dik_private')) {
      context.handle(
        _dikPrivateMeta,
        dikPrivate.isAcceptableOrUnknown(data['dik_private']!, _dikPrivateMeta),
      );
    } else if (isInserting) {
      context.missing(_dikPrivateMeta);
    }
    if (data.containsKey('dsk_public')) {
      context.handle(
        _dskPublicMeta,
        dskPublic.isAcceptableOrUnknown(data['dsk_public']!, _dskPublicMeta),
      );
    } else if (isInserting) {
      context.missing(_dskPublicMeta);
    }
    if (data.containsKey('dsk_private')) {
      context.handle(
        _dskPrivateMeta,
        dskPrivate.isAcceptableOrUnknown(data['dsk_private']!, _dskPrivateMeta),
      );
    } else if (isInserting) {
      context.missing(_dskPrivateMeta);
    }
    if (data.containsKey('device_certificate')) {
      context.handle(
        _deviceCertificateMeta,
        deviceCertificate.isAcceptableOrUnknown(
          data['device_certificate']!,
          _deviceCertificateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deviceCertificateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IdentityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IdentityRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      aikPublic: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}aik_public'],
      )!,
      aikPrivate: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}aik_private'],
      )!,
      dikPublic: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}dik_public'],
      )!,
      dikPrivate: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}dik_private'],
      )!,
      dskPublic: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}dsk_public'],
      )!,
      dskPrivate: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}dsk_private'],
      )!,
      deviceCertificate: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}device_certificate'],
      )!,
      createdAt: $IdentityTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
    );
  }

  @override
  $IdentityTable createAlias(String alias) {
    return $IdentityTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt = const EpochMs();
}

class IdentityRow extends DataClass implements Insertable<IdentityRow> {
  final int id;
  final String accountId;
  final String deviceId;
  final Uint8List aikPublic;
  final Uint8List aikPrivate;
  final Uint8List dikPublic;
  final Uint8List dikPrivate;
  final Uint8List dskPublic;
  final Uint8List dskPrivate;
  final Uint8List deviceCertificate;
  final DateTime createdAt;
  const IdentityRow({
    required this.id,
    required this.accountId,
    required this.deviceId,
    required this.aikPublic,
    required this.aikPrivate,
    required this.dikPublic,
    required this.dikPrivate,
    required this.dskPublic,
    required this.dskPrivate,
    required this.deviceCertificate,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<String>(accountId);
    map['device_id'] = Variable<String>(deviceId);
    map['aik_public'] = Variable<Uint8List>(aikPublic);
    map['aik_private'] = Variable<Uint8List>(aikPrivate);
    map['dik_public'] = Variable<Uint8List>(dikPublic);
    map['dik_private'] = Variable<Uint8List>(dikPrivate);
    map['dsk_public'] = Variable<Uint8List>(dskPublic);
    map['dsk_private'] = Variable<Uint8List>(dskPrivate);
    map['device_certificate'] = Variable<Uint8List>(deviceCertificate);
    {
      map['created_at'] = Variable<int>(
        $IdentityTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    return map;
  }

  IdentityCompanion toCompanion(bool nullToAbsent) {
    return IdentityCompanion(
      id: Value(id),
      accountId: Value(accountId),
      deviceId: Value(deviceId),
      aikPublic: Value(aikPublic),
      aikPrivate: Value(aikPrivate),
      dikPublic: Value(dikPublic),
      dikPrivate: Value(dikPrivate),
      dskPublic: Value(dskPublic),
      dskPrivate: Value(dskPrivate),
      deviceCertificate: Value(deviceCertificate),
      createdAt: Value(createdAt),
    );
  }

  factory IdentityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IdentityRow(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<String>(json['accountId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      aikPublic: serializer.fromJson<Uint8List>(json['aikPublic']),
      aikPrivate: serializer.fromJson<Uint8List>(json['aikPrivate']),
      dikPublic: serializer.fromJson<Uint8List>(json['dikPublic']),
      dikPrivate: serializer.fromJson<Uint8List>(json['dikPrivate']),
      dskPublic: serializer.fromJson<Uint8List>(json['dskPublic']),
      dskPrivate: serializer.fromJson<Uint8List>(json['dskPrivate']),
      deviceCertificate: serializer.fromJson<Uint8List>(
        json['deviceCertificate'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountId': serializer.toJson<String>(accountId),
      'deviceId': serializer.toJson<String>(deviceId),
      'aikPublic': serializer.toJson<Uint8List>(aikPublic),
      'aikPrivate': serializer.toJson<Uint8List>(aikPrivate),
      'dikPublic': serializer.toJson<Uint8List>(dikPublic),
      'dikPrivate': serializer.toJson<Uint8List>(dikPrivate),
      'dskPublic': serializer.toJson<Uint8List>(dskPublic),
      'dskPrivate': serializer.toJson<Uint8List>(dskPrivate),
      'deviceCertificate': serializer.toJson<Uint8List>(deviceCertificate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  IdentityRow copyWith({
    int? id,
    String? accountId,
    String? deviceId,
    Uint8List? aikPublic,
    Uint8List? aikPrivate,
    Uint8List? dikPublic,
    Uint8List? dikPrivate,
    Uint8List? dskPublic,
    Uint8List? dskPrivate,
    Uint8List? deviceCertificate,
    DateTime? createdAt,
  }) => IdentityRow(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    deviceId: deviceId ?? this.deviceId,
    aikPublic: aikPublic ?? this.aikPublic,
    aikPrivate: aikPrivate ?? this.aikPrivate,
    dikPublic: dikPublic ?? this.dikPublic,
    dikPrivate: dikPrivate ?? this.dikPrivate,
    dskPublic: dskPublic ?? this.dskPublic,
    dskPrivate: dskPrivate ?? this.dskPrivate,
    deviceCertificate: deviceCertificate ?? this.deviceCertificate,
    createdAt: createdAt ?? this.createdAt,
  );
  IdentityRow copyWithCompanion(IdentityCompanion data) {
    return IdentityRow(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      aikPublic: data.aikPublic.present ? data.aikPublic.value : this.aikPublic,
      aikPrivate: data.aikPrivate.present
          ? data.aikPrivate.value
          : this.aikPrivate,
      dikPublic: data.dikPublic.present ? data.dikPublic.value : this.dikPublic,
      dikPrivate: data.dikPrivate.present
          ? data.dikPrivate.value
          : this.dikPrivate,
      dskPublic: data.dskPublic.present ? data.dskPublic.value : this.dskPublic,
      dskPrivate: data.dskPrivate.present
          ? data.dskPrivate.value
          : this.dskPrivate,
      deviceCertificate: data.deviceCertificate.present
          ? data.deviceCertificate.value
          : this.deviceCertificate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IdentityRow(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('deviceId: $deviceId, ')
          ..write('aikPublic: $aikPublic, ')
          ..write('aikPrivate: $aikPrivate, ')
          ..write('dikPublic: $dikPublic, ')
          ..write('dikPrivate: $dikPrivate, ')
          ..write('dskPublic: $dskPublic, ')
          ..write('dskPrivate: $dskPrivate, ')
          ..write('deviceCertificate: $deviceCertificate, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    deviceId,
    $driftBlobEquality.hash(aikPublic),
    $driftBlobEquality.hash(aikPrivate),
    $driftBlobEquality.hash(dikPublic),
    $driftBlobEquality.hash(dikPrivate),
    $driftBlobEquality.hash(dskPublic),
    $driftBlobEquality.hash(dskPrivate),
    $driftBlobEquality.hash(deviceCertificate),
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IdentityRow &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.deviceId == this.deviceId &&
          $driftBlobEquality.equals(other.aikPublic, this.aikPublic) &&
          $driftBlobEquality.equals(other.aikPrivate, this.aikPrivate) &&
          $driftBlobEquality.equals(other.dikPublic, this.dikPublic) &&
          $driftBlobEquality.equals(other.dikPrivate, this.dikPrivate) &&
          $driftBlobEquality.equals(other.dskPublic, this.dskPublic) &&
          $driftBlobEquality.equals(other.dskPrivate, this.dskPrivate) &&
          $driftBlobEquality.equals(
            other.deviceCertificate,
            this.deviceCertificate,
          ) &&
          other.createdAt == this.createdAt);
}

class IdentityCompanion extends UpdateCompanion<IdentityRow> {
  final Value<int> id;
  final Value<String> accountId;
  final Value<String> deviceId;
  final Value<Uint8List> aikPublic;
  final Value<Uint8List> aikPrivate;
  final Value<Uint8List> dikPublic;
  final Value<Uint8List> dikPrivate;
  final Value<Uint8List> dskPublic;
  final Value<Uint8List> dskPrivate;
  final Value<Uint8List> deviceCertificate;
  final Value<DateTime> createdAt;
  const IdentityCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.aikPublic = const Value.absent(),
    this.aikPrivate = const Value.absent(),
    this.dikPublic = const Value.absent(),
    this.dikPrivate = const Value.absent(),
    this.dskPublic = const Value.absent(),
    this.dskPrivate = const Value.absent(),
    this.deviceCertificate = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  IdentityCompanion.insert({
    this.id = const Value.absent(),
    required String accountId,
    required String deviceId,
    required Uint8List aikPublic,
    required Uint8List aikPrivate,
    required Uint8List dikPublic,
    required Uint8List dikPrivate,
    required Uint8List dskPublic,
    required Uint8List dskPrivate,
    required Uint8List deviceCertificate,
    required DateTime createdAt,
  }) : accountId = Value(accountId),
       deviceId = Value(deviceId),
       aikPublic = Value(aikPublic),
       aikPrivate = Value(aikPrivate),
       dikPublic = Value(dikPublic),
       dikPrivate = Value(dikPrivate),
       dskPublic = Value(dskPublic),
       dskPrivate = Value(dskPrivate),
       deviceCertificate = Value(deviceCertificate),
       createdAt = Value(createdAt);
  static Insertable<IdentityRow> custom({
    Expression<int>? id,
    Expression<String>? accountId,
    Expression<String>? deviceId,
    Expression<Uint8List>? aikPublic,
    Expression<Uint8List>? aikPrivate,
    Expression<Uint8List>? dikPublic,
    Expression<Uint8List>? dikPrivate,
    Expression<Uint8List>? dskPublic,
    Expression<Uint8List>? dskPrivate,
    Expression<Uint8List>? deviceCertificate,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (deviceId != null) 'device_id': deviceId,
      if (aikPublic != null) 'aik_public': aikPublic,
      if (aikPrivate != null) 'aik_private': aikPrivate,
      if (dikPublic != null) 'dik_public': dikPublic,
      if (dikPrivate != null) 'dik_private': dikPrivate,
      if (dskPublic != null) 'dsk_public': dskPublic,
      if (dskPrivate != null) 'dsk_private': dskPrivate,
      if (deviceCertificate != null) 'device_certificate': deviceCertificate,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  IdentityCompanion copyWith({
    Value<int>? id,
    Value<String>? accountId,
    Value<String>? deviceId,
    Value<Uint8List>? aikPublic,
    Value<Uint8List>? aikPrivate,
    Value<Uint8List>? dikPublic,
    Value<Uint8List>? dikPrivate,
    Value<Uint8List>? dskPublic,
    Value<Uint8List>? dskPrivate,
    Value<Uint8List>? deviceCertificate,
    Value<DateTime>? createdAt,
  }) {
    return IdentityCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      deviceId: deviceId ?? this.deviceId,
      aikPublic: aikPublic ?? this.aikPublic,
      aikPrivate: aikPrivate ?? this.aikPrivate,
      dikPublic: dikPublic ?? this.dikPublic,
      dikPrivate: dikPrivate ?? this.dikPrivate,
      dskPublic: dskPublic ?? this.dskPublic,
      dskPrivate: dskPrivate ?? this.dskPrivate,
      deviceCertificate: deviceCertificate ?? this.deviceCertificate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (aikPublic.present) {
      map['aik_public'] = Variable<Uint8List>(aikPublic.value);
    }
    if (aikPrivate.present) {
      map['aik_private'] = Variable<Uint8List>(aikPrivate.value);
    }
    if (dikPublic.present) {
      map['dik_public'] = Variable<Uint8List>(dikPublic.value);
    }
    if (dikPrivate.present) {
      map['dik_private'] = Variable<Uint8List>(dikPrivate.value);
    }
    if (dskPublic.present) {
      map['dsk_public'] = Variable<Uint8List>(dskPublic.value);
    }
    if (dskPrivate.present) {
      map['dsk_private'] = Variable<Uint8List>(dskPrivate.value);
    }
    if (deviceCertificate.present) {
      map['device_certificate'] = Variable<Uint8List>(deviceCertificate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $IdentityTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentityCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('deviceId: $deviceId, ')
          ..write('aikPublic: $aikPublic, ')
          ..write('aikPrivate: $aikPrivate, ')
          ..write('dikPublic: $dikPublic, ')
          ..write('dikPrivate: $dikPrivate, ')
          ..write('dskPublic: $dskPublic, ')
          ..write('dskPrivate: $dskPrivate, ')
          ..write('deviceCertificate: $deviceCertificate, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions
    with TableInfo<$SessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerAccountIdMeta = const VerificationMeta(
    'peerAccountId',
  );
  @override
  late final GeneratedColumn<String> peerAccountId = GeneratedColumn<String>(
    'peer_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDeviceIdMeta = const VerificationMeta(
    'peerDeviceId',
  );
  @override
  late final GeneratedColumn<String> peerDeviceId = GeneratedColumn<String>(
    'peer_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<Uint8List> state = GeneratedColumn<Uint8List>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SessionsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SessionsTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    peerAccountId,
    peerDeviceId,
    slot,
    state,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_account_id')) {
      context.handle(
        _peerAccountIdMeta,
        peerAccountId.isAcceptableOrUnknown(
          data['peer_account_id']!,
          _peerAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerAccountIdMeta);
    }
    if (data.containsKey('peer_device_id')) {
      context.handle(
        _peerDeviceIdMeta,
        peerDeviceId.isAcceptableOrUnknown(
          data['peer_device_id']!,
          _peerDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerDeviceIdMeta);
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    } else if (isInserting) {
      context.missing(_slotMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerAccountId, peerDeviceId, slot};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      peerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_account_id'],
      )!,
      peerDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_device_id'],
      )!,
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}state'],
      )!,
      createdAt: $SessionsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $SessionsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt = const EpochMs();
  static TypeConverter<DateTime, int> $converterupdatedAt = const EpochMs();
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final String peerAccountId;
  final String peerDeviceId;
  final int slot;
  final Uint8List state;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SessionRow({
    required this.peerAccountId,
    required this.peerDeviceId,
    required this.slot,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_account_id'] = Variable<String>(peerAccountId);
    map['peer_device_id'] = Variable<String>(peerDeviceId);
    map['slot'] = Variable<int>(slot);
    map['state'] = Variable<Uint8List>(state);
    {
      map['created_at'] = Variable<int>(
        $SessionsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<int>(
        $SessionsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      peerAccountId: Value(peerAccountId),
      peerDeviceId: Value(peerDeviceId),
      slot: Value(slot),
      state: Value(state),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      peerAccountId: serializer.fromJson<String>(json['peerAccountId']),
      peerDeviceId: serializer.fromJson<String>(json['peerDeviceId']),
      slot: serializer.fromJson<int>(json['slot']),
      state: serializer.fromJson<Uint8List>(json['state']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerAccountId': serializer.toJson<String>(peerAccountId),
      'peerDeviceId': serializer.toJson<String>(peerDeviceId),
      'slot': serializer.toJson<int>(slot),
      'state': serializer.toJson<Uint8List>(state),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SessionRow copyWith({
    String? peerAccountId,
    String? peerDeviceId,
    int? slot,
    Uint8List? state,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SessionRow(
    peerAccountId: peerAccountId ?? this.peerAccountId,
    peerDeviceId: peerDeviceId ?? this.peerDeviceId,
    slot: slot ?? this.slot,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      peerAccountId: data.peerAccountId.present
          ? data.peerAccountId.value
          : this.peerAccountId,
      peerDeviceId: data.peerDeviceId.present
          ? data.peerDeviceId.value
          : this.peerDeviceId,
      slot: data.slot.present ? data.slot.value : this.slot,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('peerAccountId: $peerAccountId, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('slot: $slot, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    peerAccountId,
    peerDeviceId,
    slot,
    $driftBlobEquality.hash(state),
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.peerAccountId == this.peerAccountId &&
          other.peerDeviceId == this.peerDeviceId &&
          other.slot == this.slot &&
          $driftBlobEquality.equals(other.state, this.state) &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> peerAccountId;
  final Value<String> peerDeviceId;
  final Value<int> slot;
  final Value<Uint8List> state;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SessionsCompanion({
    this.peerAccountId = const Value.absent(),
    this.peerDeviceId = const Value.absent(),
    this.slot = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String peerAccountId,
    required String peerDeviceId,
    required int slot,
    required Uint8List state,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : peerAccountId = Value(peerAccountId),
       peerDeviceId = Value(peerDeviceId),
       slot = Value(slot),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SessionRow> custom({
    Expression<String>? peerAccountId,
    Expression<String>? peerDeviceId,
    Expression<int>? slot,
    Expression<Uint8List>? state,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerAccountId != null) 'peer_account_id': peerAccountId,
      if (peerDeviceId != null) 'peer_device_id': peerDeviceId,
      if (slot != null) 'slot': slot,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? peerAccountId,
    Value<String>? peerDeviceId,
    Value<int>? slot,
    Value<Uint8List>? state,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      peerAccountId: peerAccountId ?? this.peerAccountId,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      slot: slot ?? this.slot,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerAccountId.present) {
      map['peer_account_id'] = Variable<String>(peerAccountId.value);
    }
    if (peerDeviceId.present) {
      map['peer_device_id'] = Variable<String>(peerDeviceId.value);
    }
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (state.present) {
      map['state'] = Variable<Uint8List>(state.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $SessionsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $SessionsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('peerAccountId: $peerAccountId, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('slot: $slot, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PrekeysTable extends Prekeys with TableInfo<$PrekeysTable, PrekeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PrekeysTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumnWithTypeConverter<PrekeyKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PrekeyKind>($PrekeysTable.$converterkind);
  static const VerificationMeta _keyIdMeta = const VerificationMeta('keyId');
  @override
  late final GeneratedColumn<int> keyId = GeneratedColumn<int>(
    'key_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<Uint8List> publicKey = GeneratedColumn<Uint8List>(
    'public_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _privateKeyMeta = const VerificationMeta(
    'privateKey',
  );
  @override
  late final GeneratedColumn<Uint8List> privateKey = GeneratedColumn<Uint8List>(
    'private_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<Uint8List> signature = GeneratedColumn<Uint8List>(
    'signature',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PrekeysTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> retiredAt =
      GeneratedColumn<int>(
        'retired_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($PrekeysTable.$converterretiredAtn);
  @override
  List<GeneratedColumn> get $columns => [
    kind,
    keyId,
    publicKey,
    privateKey,
    signature,
    createdAt,
    retiredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prekeys';
  @override
  VerificationContext validateIntegrity(
    Insertable<PrekeyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_id')) {
      context.handle(
        _keyIdMeta,
        keyId.isAcceptableOrUnknown(data['key_id']!, _keyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_keyIdMeta);
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_publicKeyMeta);
    }
    if (data.containsKey('private_key')) {
      context.handle(
        _privateKeyMeta,
        privateKey.isAcceptableOrUnknown(data['private_key']!, _privateKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_privateKeyMeta);
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, keyId};
  @override
  PrekeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrekeyRow(
      kind: $PrekeysTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      keyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_id'],
      )!,
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}public_key'],
      )!,
      privateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}private_key'],
      )!,
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}signature'],
      ),
      createdAt: $PrekeysTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      retiredAt: $PrekeysTable.$converterretiredAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}retired_at'],
        ),
      ),
    );
  }

  @override
  $PrekeysTable createAlias(String alias) {
    return $PrekeysTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PrekeyKind, String, String> $converterkind =
      const EnumNameConverter<PrekeyKind>(PrekeyKind.values);
  static TypeConverter<DateTime, int> $convertercreatedAt = const EpochMs();
  static TypeConverter<DateTime, int> $converterretiredAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterretiredAtn =
      NullAwareTypeConverter.wrap($converterretiredAt);
}

class PrekeyRow extends DataClass implements Insertable<PrekeyRow> {
  final PrekeyKind kind;
  final int keyId;
  final Uint8List publicKey;
  final Uint8List privateKey;
  final Uint8List? signature;
  final DateTime createdAt;
  final DateTime? retiredAt;
  const PrekeyRow({
    required this.kind,
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
    this.signature,
    required this.createdAt,
    this.retiredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    {
      map['kind'] = Variable<String>($PrekeysTable.$converterkind.toSql(kind));
    }
    map['key_id'] = Variable<int>(keyId);
    map['public_key'] = Variable<Uint8List>(publicKey);
    map['private_key'] = Variable<Uint8List>(privateKey);
    if (!nullToAbsent || signature != null) {
      map['signature'] = Variable<Uint8List>(signature);
    }
    {
      map['created_at'] = Variable<int>(
        $PrekeysTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    if (!nullToAbsent || retiredAt != null) {
      map['retired_at'] = Variable<int>(
        $PrekeysTable.$converterretiredAtn.toSql(retiredAt),
      );
    }
    return map;
  }

  PrekeysCompanion toCompanion(bool nullToAbsent) {
    return PrekeysCompanion(
      kind: Value(kind),
      keyId: Value(keyId),
      publicKey: Value(publicKey),
      privateKey: Value(privateKey),
      signature: signature == null && nullToAbsent
          ? const Value.absent()
          : Value(signature),
      createdAt: Value(createdAt),
      retiredAt: retiredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(retiredAt),
    );
  }

  factory PrekeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrekeyRow(
      kind: $PrekeysTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      keyId: serializer.fromJson<int>(json['keyId']),
      publicKey: serializer.fromJson<Uint8List>(json['publicKey']),
      privateKey: serializer.fromJson<Uint8List>(json['privateKey']),
      signature: serializer.fromJson<Uint8List?>(json['signature']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      retiredAt: serializer.fromJson<DateTime?>(json['retiredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(
        $PrekeysTable.$converterkind.toJson(kind),
      ),
      'keyId': serializer.toJson<int>(keyId),
      'publicKey': serializer.toJson<Uint8List>(publicKey),
      'privateKey': serializer.toJson<Uint8List>(privateKey),
      'signature': serializer.toJson<Uint8List?>(signature),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'retiredAt': serializer.toJson<DateTime?>(retiredAt),
    };
  }

  PrekeyRow copyWith({
    PrekeyKind? kind,
    int? keyId,
    Uint8List? publicKey,
    Uint8List? privateKey,
    Value<Uint8List?> signature = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> retiredAt = const Value.absent(),
  }) => PrekeyRow(
    kind: kind ?? this.kind,
    keyId: keyId ?? this.keyId,
    publicKey: publicKey ?? this.publicKey,
    privateKey: privateKey ?? this.privateKey,
    signature: signature.present ? signature.value : this.signature,
    createdAt: createdAt ?? this.createdAt,
    retiredAt: retiredAt.present ? retiredAt.value : this.retiredAt,
  );
  PrekeyRow copyWithCompanion(PrekeysCompanion data) {
    return PrekeyRow(
      kind: data.kind.present ? data.kind.value : this.kind,
      keyId: data.keyId.present ? data.keyId.value : this.keyId,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      privateKey: data.privateKey.present
          ? data.privateKey.value
          : this.privateKey,
      signature: data.signature.present ? data.signature.value : this.signature,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      retiredAt: data.retiredAt.present ? data.retiredAt.value : this.retiredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrekeyRow(')
          ..write('kind: $kind, ')
          ..write('keyId: $keyId, ')
          ..write('publicKey: $publicKey, ')
          ..write('privateKey: $privateKey, ')
          ..write('signature: $signature, ')
          ..write('createdAt: $createdAt, ')
          ..write('retiredAt: $retiredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    kind,
    keyId,
    $driftBlobEquality.hash(publicKey),
    $driftBlobEquality.hash(privateKey),
    $driftBlobEquality.hash(signature),
    createdAt,
    retiredAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrekeyRow &&
          other.kind == this.kind &&
          other.keyId == this.keyId &&
          $driftBlobEquality.equals(other.publicKey, this.publicKey) &&
          $driftBlobEquality.equals(other.privateKey, this.privateKey) &&
          $driftBlobEquality.equals(other.signature, this.signature) &&
          other.createdAt == this.createdAt &&
          other.retiredAt == this.retiredAt);
}

class PrekeysCompanion extends UpdateCompanion<PrekeyRow> {
  final Value<PrekeyKind> kind;
  final Value<int> keyId;
  final Value<Uint8List> publicKey;
  final Value<Uint8List> privateKey;
  final Value<Uint8List?> signature;
  final Value<DateTime> createdAt;
  final Value<DateTime?> retiredAt;
  final Value<int> rowid;
  const PrekeysCompanion({
    this.kind = const Value.absent(),
    this.keyId = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.privateKey = const Value.absent(),
    this.signature = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.retiredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PrekeysCompanion.insert({
    required PrekeyKind kind,
    required int keyId,
    required Uint8List publicKey,
    required Uint8List privateKey,
    this.signature = const Value.absent(),
    required DateTime createdAt,
    this.retiredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       keyId = Value(keyId),
       publicKey = Value(publicKey),
       privateKey = Value(privateKey),
       createdAt = Value(createdAt);
  static Insertable<PrekeyRow> custom({
    Expression<String>? kind,
    Expression<int>? keyId,
    Expression<Uint8List>? publicKey,
    Expression<Uint8List>? privateKey,
    Expression<Uint8List>? signature,
    Expression<int>? createdAt,
    Expression<int>? retiredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (keyId != null) 'key_id': keyId,
      if (publicKey != null) 'public_key': publicKey,
      if (privateKey != null) 'private_key': privateKey,
      if (signature != null) 'signature': signature,
      if (createdAt != null) 'created_at': createdAt,
      if (retiredAt != null) 'retired_at': retiredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PrekeysCompanion copyWith({
    Value<PrekeyKind>? kind,
    Value<int>? keyId,
    Value<Uint8List>? publicKey,
    Value<Uint8List>? privateKey,
    Value<Uint8List?>? signature,
    Value<DateTime>? createdAt,
    Value<DateTime?>? retiredAt,
    Value<int>? rowid,
  }) {
    return PrekeysCompanion(
      kind: kind ?? this.kind,
      keyId: keyId ?? this.keyId,
      publicKey: publicKey ?? this.publicKey,
      privateKey: privateKey ?? this.privateKey,
      signature: signature ?? this.signature,
      createdAt: createdAt ?? this.createdAt,
      retiredAt: retiredAt ?? this.retiredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(
        $PrekeysTable.$converterkind.toSql(kind.value),
      );
    }
    if (keyId.present) {
      map['key_id'] = Variable<int>(keyId.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<Uint8List>(publicKey.value);
    }
    if (privateKey.present) {
      map['private_key'] = Variable<Uint8List>(privateKey.value);
    }
    if (signature.present) {
      map['signature'] = Variable<Uint8List>(signature.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $PrekeysTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (retiredAt.present) {
      map['retired_at'] = Variable<int>(
        $PrekeysTable.$converterretiredAtn.toSql(retiredAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrekeysCompanion(')
          ..write('kind: $kind, ')
          ..write('keyId: $keyId, ')
          ..write('publicKey: $publicKey, ')
          ..write('privateKey: $privateKey, ')
          ..write('signature: $signature, ')
          ..write('createdAt: $createdAt, ')
          ..write('retiredAt: $retiredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SenderKeysTable extends SenderKeys
    with TableInfo<$SenderKeysTable, SenderKeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SenderKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distIdMeta = const VerificationMeta('distId');
  @override
  late final GeneratedColumn<String> distId = GeneratedColumn<String>(
    'dist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<Uint8List> state = GeneratedColumn<Uint8List>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SenderKeysTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SenderKeysTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    accountId,
    deviceId,
    distId,
    state,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sender_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<SenderKeyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('dist_id')) {
      context.handle(
        _distIdMeta,
        distId.isAcceptableOrUnknown(data['dist_id']!, _distIdMeta),
      );
    } else if (isInserting) {
      context.missing(_distIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    groupId,
    accountId,
    deviceId,
    distId,
  };
  @override
  SenderKeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SenderKeyRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      distId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dist_id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}state'],
      )!,
      createdAt: $SenderKeysTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $SenderKeysTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $SenderKeysTable createAlias(String alias) {
    return $SenderKeysTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertercreatedAt = const EpochMs();
  static TypeConverter<DateTime, int> $converterupdatedAt = const EpochMs();
}

class SenderKeyRow extends DataClass implements Insertable<SenderKeyRow> {
  final String groupId;
  final String accountId;
  final String deviceId;
  final String distId;
  final Uint8List state;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SenderKeyRow({
    required this.groupId,
    required this.accountId,
    required this.deviceId,
    required this.distId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['account_id'] = Variable<String>(accountId);
    map['device_id'] = Variable<String>(deviceId);
    map['dist_id'] = Variable<String>(distId);
    map['state'] = Variable<Uint8List>(state);
    {
      map['created_at'] = Variable<int>(
        $SenderKeysTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<int>(
        $SenderKeysTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  SenderKeysCompanion toCompanion(bool nullToAbsent) {
    return SenderKeysCompanion(
      groupId: Value(groupId),
      accountId: Value(accountId),
      deviceId: Value(deviceId),
      distId: Value(distId),
      state: Value(state),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SenderKeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SenderKeyRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      distId: serializer.fromJson<String>(json['distId']),
      state: serializer.fromJson<Uint8List>(json['state']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'accountId': serializer.toJson<String>(accountId),
      'deviceId': serializer.toJson<String>(deviceId),
      'distId': serializer.toJson<String>(distId),
      'state': serializer.toJson<Uint8List>(state),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SenderKeyRow copyWith({
    String? groupId,
    String? accountId,
    String? deviceId,
    String? distId,
    Uint8List? state,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SenderKeyRow(
    groupId: groupId ?? this.groupId,
    accountId: accountId ?? this.accountId,
    deviceId: deviceId ?? this.deviceId,
    distId: distId ?? this.distId,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SenderKeyRow copyWithCompanion(SenderKeysCompanion data) {
    return SenderKeyRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      distId: data.distId.present ? data.distId.value : this.distId,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SenderKeyRow(')
          ..write('groupId: $groupId, ')
          ..write('accountId: $accountId, ')
          ..write('deviceId: $deviceId, ')
          ..write('distId: $distId, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    accountId,
    deviceId,
    distId,
    $driftBlobEquality.hash(state),
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SenderKeyRow &&
          other.groupId == this.groupId &&
          other.accountId == this.accountId &&
          other.deviceId == this.deviceId &&
          other.distId == this.distId &&
          $driftBlobEquality.equals(other.state, this.state) &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SenderKeysCompanion extends UpdateCompanion<SenderKeyRow> {
  final Value<String> groupId;
  final Value<String> accountId;
  final Value<String> deviceId;
  final Value<String> distId;
  final Value<Uint8List> state;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SenderKeysCompanion({
    this.groupId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.distId = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SenderKeysCompanion.insert({
    required String groupId,
    required String accountId,
    required String deviceId,
    required String distId,
    required Uint8List state,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       accountId = Value(accountId),
       deviceId = Value(deviceId),
       distId = Value(distId),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SenderKeyRow> custom({
    Expression<String>? groupId,
    Expression<String>? accountId,
    Expression<String>? deviceId,
    Expression<String>? distId,
    Expression<Uint8List>? state,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (accountId != null) 'account_id': accountId,
      if (deviceId != null) 'device_id': deviceId,
      if (distId != null) 'dist_id': distId,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SenderKeysCompanion copyWith({
    Value<String>? groupId,
    Value<String>? accountId,
    Value<String>? deviceId,
    Value<String>? distId,
    Value<Uint8List>? state,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SenderKeysCompanion(
      groupId: groupId ?? this.groupId,
      accountId: accountId ?? this.accountId,
      deviceId: deviceId ?? this.deviceId,
      distId: distId ?? this.distId,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (distId.present) {
      map['dist_id'] = Variable<String>(distId.value);
    }
    if (state.present) {
      map['state'] = Variable<Uint8List>(state.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $SenderKeysTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $SenderKeysTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SenderKeysCompanion(')
          ..write('groupId: $groupId, ')
          ..write('accountId: $accountId, ')
          ..write('deviceId: $deviceId, ')
          ..write('distId: $distId, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InboxCursorTable extends InboxCursor
    with TableInfo<$InboxCursorTable, InboxCursorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InboxCursorTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastProcessedSeqMeta = const VerificationMeta(
    'lastProcessedSeq',
  );
  @override
  late final GeneratedColumn<int> lastProcessedSeq = GeneratedColumn<int>(
    'last_processed_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAckedSeqMeta = const VerificationMeta(
    'lastAckedSeq',
  );
  @override
  late final GeneratedColumn<int> lastAckedSeq = GeneratedColumn<int>(
    'last_acked_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($InboxCursorTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lastProcessedSeq,
    lastAckedSeq,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inbox_cursor';
  @override
  VerificationContext validateIntegrity(
    Insertable<InboxCursorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_processed_seq')) {
      context.handle(
        _lastProcessedSeqMeta,
        lastProcessedSeq.isAcceptableOrUnknown(
          data['last_processed_seq']!,
          _lastProcessedSeqMeta,
        ),
      );
    }
    if (data.containsKey('last_acked_seq')) {
      context.handle(
        _lastAckedSeqMeta,
        lastAckedSeq.isAcceptableOrUnknown(
          data['last_acked_seq']!,
          _lastAckedSeqMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InboxCursorRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InboxCursorRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lastProcessedSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_processed_seq'],
      )!,
      lastAckedSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_acked_seq'],
      )!,
      updatedAt: $InboxCursorTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $InboxCursorTable createAlias(String alias) {
    return $InboxCursorTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterupdatedAt = const EpochMs();
}

class InboxCursorRow extends DataClass implements Insertable<InboxCursorRow> {
  final int id;

  /// Highest `seq` durably processed (sent as `after` on reconnect).
  final int lastProcessedSeq;

  /// Highest `seq` acked to the server.
  final int lastAckedSeq;
  final DateTime updatedAt;
  const InboxCursorRow({
    required this.id,
    required this.lastProcessedSeq,
    required this.lastAckedSeq,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['last_processed_seq'] = Variable<int>(lastProcessedSeq);
    map['last_acked_seq'] = Variable<int>(lastAckedSeq);
    {
      map['updated_at'] = Variable<int>(
        $InboxCursorTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  InboxCursorCompanion toCompanion(bool nullToAbsent) {
    return InboxCursorCompanion(
      id: Value(id),
      lastProcessedSeq: Value(lastProcessedSeq),
      lastAckedSeq: Value(lastAckedSeq),
      updatedAt: Value(updatedAt),
    );
  }

  factory InboxCursorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InboxCursorRow(
      id: serializer.fromJson<int>(json['id']),
      lastProcessedSeq: serializer.fromJson<int>(json['lastProcessedSeq']),
      lastAckedSeq: serializer.fromJson<int>(json['lastAckedSeq']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lastProcessedSeq': serializer.toJson<int>(lastProcessedSeq),
      'lastAckedSeq': serializer.toJson<int>(lastAckedSeq),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  InboxCursorRow copyWith({
    int? id,
    int? lastProcessedSeq,
    int? lastAckedSeq,
    DateTime? updatedAt,
  }) => InboxCursorRow(
    id: id ?? this.id,
    lastProcessedSeq: lastProcessedSeq ?? this.lastProcessedSeq,
    lastAckedSeq: lastAckedSeq ?? this.lastAckedSeq,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  InboxCursorRow copyWithCompanion(InboxCursorCompanion data) {
    return InboxCursorRow(
      id: data.id.present ? data.id.value : this.id,
      lastProcessedSeq: data.lastProcessedSeq.present
          ? data.lastProcessedSeq.value
          : this.lastProcessedSeq,
      lastAckedSeq: data.lastAckedSeq.present
          ? data.lastAckedSeq.value
          : this.lastAckedSeq,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InboxCursorRow(')
          ..write('id: $id, ')
          ..write('lastProcessedSeq: $lastProcessedSeq, ')
          ..write('lastAckedSeq: $lastAckedSeq, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, lastProcessedSeq, lastAckedSeq, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InboxCursorRow &&
          other.id == this.id &&
          other.lastProcessedSeq == this.lastProcessedSeq &&
          other.lastAckedSeq == this.lastAckedSeq &&
          other.updatedAt == this.updatedAt);
}

class InboxCursorCompanion extends UpdateCompanion<InboxCursorRow> {
  final Value<int> id;
  final Value<int> lastProcessedSeq;
  final Value<int> lastAckedSeq;
  final Value<DateTime> updatedAt;
  const InboxCursorCompanion({
    this.id = const Value.absent(),
    this.lastProcessedSeq = const Value.absent(),
    this.lastAckedSeq = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  InboxCursorCompanion.insert({
    this.id = const Value.absent(),
    this.lastProcessedSeq = const Value.absent(),
    this.lastAckedSeq = const Value.absent(),
    required DateTime updatedAt,
  }) : updatedAt = Value(updatedAt);
  static Insertable<InboxCursorRow> custom({
    Expression<int>? id,
    Expression<int>? lastProcessedSeq,
    Expression<int>? lastAckedSeq,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lastProcessedSeq != null) 'last_processed_seq': lastProcessedSeq,
      if (lastAckedSeq != null) 'last_acked_seq': lastAckedSeq,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  InboxCursorCompanion copyWith({
    Value<int>? id,
    Value<int>? lastProcessedSeq,
    Value<int>? lastAckedSeq,
    Value<DateTime>? updatedAt,
  }) {
    return InboxCursorCompanion(
      id: id ?? this.id,
      lastProcessedSeq: lastProcessedSeq ?? this.lastProcessedSeq,
      lastAckedSeq: lastAckedSeq ?? this.lastAckedSeq,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lastProcessedSeq.present) {
      map['last_processed_seq'] = Variable<int>(lastProcessedSeq.value);
    }
    if (lastAckedSeq.present) {
      map['last_acked_seq'] = Variable<int>(lastAckedSeq.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $InboxCursorTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InboxCursorCompanion(')
          ..write('id: $id, ')
          ..write('lastProcessedSeq: $lastProcessedSeq, ')
          ..write('lastAckedSeq: $lastAckedSeq, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProcessedEnvelopesTable extends ProcessedEnvelopes
    with TableInfo<$ProcessedEnvelopesTable, ProcessedEnvelopeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProcessedEnvelopesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _envelopeIdMeta = const VerificationMeta(
    'envelopeId',
  );
  @override
  late final GeneratedColumn<String> envelopeId = GeneratedColumn<String>(
    'envelope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderDeviceMeta = const VerificationMeta(
    'senderDevice',
  );
  @override
  late final GeneratedColumn<String> senderDevice = GeneratedColumn<String>(
    'sender_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EnvelopeOutcome, String> outcome =
      GeneratedColumn<String>(
        'outcome',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EnvelopeOutcome>(
        $ProcessedEnvelopesTable.$converteroutcome,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> processedAt =
      GeneratedColumn<int>(
        'processed_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($ProcessedEnvelopesTable.$converterprocessedAt);
  @override
  List<GeneratedColumn> get $columns => [
    envelopeId,
    senderDevice,
    seq,
    outcome,
    processedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'processed_envelopes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProcessedEnvelopeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('envelope_id')) {
      context.handle(
        _envelopeIdMeta,
        envelopeId.isAcceptableOrUnknown(data['envelope_id']!, _envelopeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_envelopeIdMeta);
    }
    if (data.containsKey('sender_device')) {
      context.handle(
        _senderDeviceMeta,
        senderDevice.isAcceptableOrUnknown(
          data['sender_device']!,
          _senderDeviceMeta,
        ),
      );
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {envelopeId, senderDevice};
  @override
  ProcessedEnvelopeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProcessedEnvelopeRow(
      envelopeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope_id'],
      )!,
      senderDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_device'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      ),
      outcome: $ProcessedEnvelopesTable.$converteroutcome.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}outcome'],
        )!,
      ),
      processedAt: $ProcessedEnvelopesTable.$converterprocessedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}processed_at'],
        )!,
      ),
    );
  }

  @override
  $ProcessedEnvelopesTable createAlias(String alias) {
    return $ProcessedEnvelopesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EnvelopeOutcome, String, String> $converteroutcome =
      const EnumNameConverter<EnvelopeOutcome>(EnvelopeOutcome.values);
  static TypeConverter<DateTime, int> $converterprocessedAt = const EpochMs();
}

class ProcessedEnvelopeRow extends DataClass
    implements Insertable<ProcessedEnvelopeRow> {
  final String envelopeId;

  /// Empty for envelopes the server generates.
  final String senderDevice;
  final int? seq;
  final EnvelopeOutcome outcome;
  final DateTime processedAt;
  const ProcessedEnvelopeRow({
    required this.envelopeId,
    required this.senderDevice,
    this.seq,
    required this.outcome,
    required this.processedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['envelope_id'] = Variable<String>(envelopeId);
    map['sender_device'] = Variable<String>(senderDevice);
    if (!nullToAbsent || seq != null) {
      map['seq'] = Variable<int>(seq);
    }
    {
      map['outcome'] = Variable<String>(
        $ProcessedEnvelopesTable.$converteroutcome.toSql(outcome),
      );
    }
    {
      map['processed_at'] = Variable<int>(
        $ProcessedEnvelopesTable.$converterprocessedAt.toSql(processedAt),
      );
    }
    return map;
  }

  ProcessedEnvelopesCompanion toCompanion(bool nullToAbsent) {
    return ProcessedEnvelopesCompanion(
      envelopeId: Value(envelopeId),
      senderDevice: Value(senderDevice),
      seq: seq == null && nullToAbsent ? const Value.absent() : Value(seq),
      outcome: Value(outcome),
      processedAt: Value(processedAt),
    );
  }

  factory ProcessedEnvelopeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProcessedEnvelopeRow(
      envelopeId: serializer.fromJson<String>(json['envelopeId']),
      senderDevice: serializer.fromJson<String>(json['senderDevice']),
      seq: serializer.fromJson<int?>(json['seq']),
      outcome: $ProcessedEnvelopesTable.$converteroutcome.fromJson(
        serializer.fromJson<String>(json['outcome']),
      ),
      processedAt: serializer.fromJson<DateTime>(json['processedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'envelopeId': serializer.toJson<String>(envelopeId),
      'senderDevice': serializer.toJson<String>(senderDevice),
      'seq': serializer.toJson<int?>(seq),
      'outcome': serializer.toJson<String>(
        $ProcessedEnvelopesTable.$converteroutcome.toJson(outcome),
      ),
      'processedAt': serializer.toJson<DateTime>(processedAt),
    };
  }

  ProcessedEnvelopeRow copyWith({
    String? envelopeId,
    String? senderDevice,
    Value<int?> seq = const Value.absent(),
    EnvelopeOutcome? outcome,
    DateTime? processedAt,
  }) => ProcessedEnvelopeRow(
    envelopeId: envelopeId ?? this.envelopeId,
    senderDevice: senderDevice ?? this.senderDevice,
    seq: seq.present ? seq.value : this.seq,
    outcome: outcome ?? this.outcome,
    processedAt: processedAt ?? this.processedAt,
  );
  ProcessedEnvelopeRow copyWithCompanion(ProcessedEnvelopesCompanion data) {
    return ProcessedEnvelopeRow(
      envelopeId: data.envelopeId.present
          ? data.envelopeId.value
          : this.envelopeId,
      senderDevice: data.senderDevice.present
          ? data.senderDevice.value
          : this.senderDevice,
      seq: data.seq.present ? data.seq.value : this.seq,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      processedAt: data.processedAt.present
          ? data.processedAt.value
          : this.processedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedEnvelopeRow(')
          ..write('envelopeId: $envelopeId, ')
          ..write('senderDevice: $senderDevice, ')
          ..write('seq: $seq, ')
          ..write('outcome: $outcome, ')
          ..write('processedAt: $processedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(envelopeId, senderDevice, seq, outcome, processedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProcessedEnvelopeRow &&
          other.envelopeId == this.envelopeId &&
          other.senderDevice == this.senderDevice &&
          other.seq == this.seq &&
          other.outcome == this.outcome &&
          other.processedAt == this.processedAt);
}

class ProcessedEnvelopesCompanion
    extends UpdateCompanion<ProcessedEnvelopeRow> {
  final Value<String> envelopeId;
  final Value<String> senderDevice;
  final Value<int?> seq;
  final Value<EnvelopeOutcome> outcome;
  final Value<DateTime> processedAt;
  final Value<int> rowid;
  const ProcessedEnvelopesCompanion({
    this.envelopeId = const Value.absent(),
    this.senderDevice = const Value.absent(),
    this.seq = const Value.absent(),
    this.outcome = const Value.absent(),
    this.processedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProcessedEnvelopesCompanion.insert({
    required String envelopeId,
    this.senderDevice = const Value.absent(),
    this.seq = const Value.absent(),
    required EnvelopeOutcome outcome,
    required DateTime processedAt,
    this.rowid = const Value.absent(),
  }) : envelopeId = Value(envelopeId),
       outcome = Value(outcome),
       processedAt = Value(processedAt);
  static Insertable<ProcessedEnvelopeRow> custom({
    Expression<String>? envelopeId,
    Expression<String>? senderDevice,
    Expression<int>? seq,
    Expression<String>? outcome,
    Expression<int>? processedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (envelopeId != null) 'envelope_id': envelopeId,
      if (senderDevice != null) 'sender_device': senderDevice,
      if (seq != null) 'seq': seq,
      if (outcome != null) 'outcome': outcome,
      if (processedAt != null) 'processed_at': processedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProcessedEnvelopesCompanion copyWith({
    Value<String>? envelopeId,
    Value<String>? senderDevice,
    Value<int?>? seq,
    Value<EnvelopeOutcome>? outcome,
    Value<DateTime>? processedAt,
    Value<int>? rowid,
  }) {
    return ProcessedEnvelopesCompanion(
      envelopeId: envelopeId ?? this.envelopeId,
      senderDevice: senderDevice ?? this.senderDevice,
      seq: seq ?? this.seq,
      outcome: outcome ?? this.outcome,
      processedAt: processedAt ?? this.processedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (envelopeId.present) {
      map['envelope_id'] = Variable<String>(envelopeId.value);
    }
    if (senderDevice.present) {
      map['sender_device'] = Variable<String>(senderDevice.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(
        $ProcessedEnvelopesTable.$converteroutcome.toSql(outcome.value),
      );
    }
    if (processedAt.present) {
      map['processed_at'] = Variable<int>(
        $ProcessedEnvelopesTable.$converterprocessedAt.toSql(processedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedEnvelopesCompanion(')
          ..write('envelopeId: $envelopeId, ')
          ..write('senderDevice: $senderDevice, ')
          ..write('seq: $seq, ')
          ..write('outcome: $outcome, ')
          ..write('processedAt: $processedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxOpsTable extends OutboxOps
    with TableInfo<$OutboxOpsTable, OutboxOpRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxOpsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _messageRowidMeta = const VerificationMeta(
    'messageRowid',
  );
  @override
  late final GeneratedColumn<int> messageRowid = GeneratedColumn<int>(
    'message_rowid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (local_rowid) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<OutboxState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<OutboxState>($OutboxOpsTable.$converterstate);
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> nextAttemptAt =
      GeneratedColumn<int>(
        'next_attempt_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($OutboxOpsTable.$converternextAttemptAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> leaseUntil =
      GeneratedColumn<int>(
        'lease_until',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($OutboxOpsTable.$converterleaseUntiln);
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($OutboxOpsTable.$convertercreatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    conversationId,
    messageRowid,
    idempotencyKey,
    payload,
    state,
    attempts,
    nextAttemptAt,
    leaseUntil,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_ops';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxOpRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    }
    if (data.containsKey('message_rowid')) {
      context.handle(
        _messageRowidMeta,
        messageRowid.isAcceptableOrUnknown(
          data['message_rowid']!,
          _messageRowidMeta,
        ),
      );
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxOpRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxOpRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      ),
      messageRowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_rowid'],
      ),
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      state: $OutboxOpsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: $OutboxOpsTable.$converternextAttemptAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}next_attempt_at'],
        )!,
      ),
      leaseUntil: $OutboxOpsTable.$converterleaseUntiln.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}lease_until'],
        ),
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: $OutboxOpsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
    );
  }

  @override
  $OutboxOpsTable createAlias(String alias) {
    return $OutboxOpsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<OutboxState, String, String> $converterstate =
      const EnumNameConverter<OutboxState>(OutboxState.values);
  static TypeConverter<DateTime, int> $converternextAttemptAt = const EpochMs();
  static TypeConverter<DateTime, int> $converterleaseUntil = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterleaseUntiln =
      NullAwareTypeConverter.wrap($converterleaseUntil);
  static TypeConverter<DateTime, int> $convertercreatedAt = const EpochMs();
}

class OutboxOpRow extends DataClass implements Insertable<OutboxOpRow> {
  final int id;

  /// What to do (`send_message`, `send_receipt`, …); the engine defines it.
  final String kind;
  final String? conversationId;
  final int? messageRowid;
  final String idempotencyKey;

  /// Plaintext to encrypt at send time (JSON).
  final String payload;
  final OutboxState state;
  final int attempts;
  final DateTime nextAttemptAt;
  final DateTime? leaseUntil;

  /// An error code only, never content.
  final String? lastError;
  final DateTime createdAt;
  const OutboxOpRow({
    required this.id,
    required this.kind,
    this.conversationId,
    this.messageRowid,
    required this.idempotencyKey,
    required this.payload,
    required this.state,
    required this.attempts,
    required this.nextAttemptAt,
    this.leaseUntil,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || conversationId != null) {
      map['conversation_id'] = Variable<String>(conversationId);
    }
    if (!nullToAbsent || messageRowid != null) {
      map['message_rowid'] = Variable<int>(messageRowid);
    }
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['payload'] = Variable<String>(payload);
    {
      map['state'] = Variable<String>(
        $OutboxOpsTable.$converterstate.toSql(state),
      );
    }
    map['attempts'] = Variable<int>(attempts);
    {
      map['next_attempt_at'] = Variable<int>(
        $OutboxOpsTable.$converternextAttemptAt.toSql(nextAttemptAt),
      );
    }
    if (!nullToAbsent || leaseUntil != null) {
      map['lease_until'] = Variable<int>(
        $OutboxOpsTable.$converterleaseUntiln.toSql(leaseUntil),
      );
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    {
      map['created_at'] = Variable<int>(
        $OutboxOpsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    return map;
  }

  OutboxOpsCompanion toCompanion(bool nullToAbsent) {
    return OutboxOpsCompanion(
      id: Value(id),
      kind: Value(kind),
      conversationId: conversationId == null && nullToAbsent
          ? const Value.absent()
          : Value(conversationId),
      messageRowid: messageRowid == null && nullToAbsent
          ? const Value.absent()
          : Value(messageRowid),
      idempotencyKey: Value(idempotencyKey),
      payload: Value(payload),
      state: Value(state),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      leaseUntil: leaseUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseUntil),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxOpRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxOpRow(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      conversationId: serializer.fromJson<String?>(json['conversationId']),
      messageRowid: serializer.fromJson<int?>(json['messageRowid']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      payload: serializer.fromJson<String>(json['payload']),
      state: $OutboxOpsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime>(json['nextAttemptAt']),
      leaseUntil: serializer.fromJson<DateTime?>(json['leaseUntil']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'conversationId': serializer.toJson<String?>(conversationId),
      'messageRowid': serializer.toJson<int?>(messageRowid),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'payload': serializer.toJson<String>(payload),
      'state': serializer.toJson<String>(
        $OutboxOpsTable.$converterstate.toJson(state),
      ),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime>(nextAttemptAt),
      'leaseUntil': serializer.toJson<DateTime?>(leaseUntil),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxOpRow copyWith({
    int? id,
    String? kind,
    Value<String?> conversationId = const Value.absent(),
    Value<int?> messageRowid = const Value.absent(),
    String? idempotencyKey,
    String? payload,
    OutboxState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    Value<DateTime?> leaseUntil = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => OutboxOpRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    conversationId: conversationId.present
        ? conversationId.value
        : this.conversationId,
    messageRowid: messageRowid.present ? messageRowid.value : this.messageRowid,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    payload: payload ?? this.payload,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    leaseUntil: leaseUntil.present ? leaseUntil.value : this.leaseUntil,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxOpRow copyWithCompanion(OutboxOpsCompanion data) {
    return OutboxOpRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      messageRowid: data.messageRowid.present
          ? data.messageRowid.value
          : this.messageRowid,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      payload: data.payload.present ? data.payload.value : this.payload,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      leaseUntil: data.leaseUntil.present
          ? data.leaseUntil.value
          : this.leaseUntil,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOpRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('conversationId: $conversationId, ')
          ..write('messageRowid: $messageRowid, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('leaseUntil: $leaseUntil, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    conversationId,
    messageRowid,
    idempotencyKey,
    payload,
    state,
    attempts,
    nextAttemptAt,
    leaseUntil,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxOpRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.conversationId == this.conversationId &&
          other.messageRowid == this.messageRowid &&
          other.idempotencyKey == this.idempotencyKey &&
          other.payload == this.payload &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.leaseUntil == this.leaseUntil &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class OutboxOpsCompanion extends UpdateCompanion<OutboxOpRow> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String?> conversationId;
  final Value<int?> messageRowid;
  final Value<String> idempotencyKey;
  final Value<String> payload;
  final Value<OutboxState> state;
  final Value<int> attempts;
  final Value<DateTime> nextAttemptAt;
  final Value<DateTime?> leaseUntil;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  const OutboxOpsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.messageRowid = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.payload = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.leaseUntil = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OutboxOpsCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    this.conversationId = const Value.absent(),
    this.messageRowid = const Value.absent(),
    required String idempotencyKey,
    required String payload,
    required OutboxState state,
    this.attempts = const Value.absent(),
    required DateTime nextAttemptAt,
    this.leaseUntil = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
  }) : kind = Value(kind),
       idempotencyKey = Value(idempotencyKey),
       payload = Value(payload),
       state = Value(state),
       nextAttemptAt = Value(nextAttemptAt),
       createdAt = Value(createdAt);
  static Insertable<OutboxOpRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? conversationId,
    Expression<int>? messageRowid,
    Expression<String>? idempotencyKey,
    Expression<String>? payload,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<int>? leaseUntil,
    Expression<String>? lastError,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (conversationId != null) 'conversation_id': conversationId,
      if (messageRowid != null) 'message_rowid': messageRowid,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (payload != null) 'payload': payload,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (leaseUntil != null) 'lease_until': leaseUntil,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OutboxOpsCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String?>? conversationId,
    Value<int?>? messageRowid,
    Value<String>? idempotencyKey,
    Value<String>? payload,
    Value<OutboxState>? state,
    Value<int>? attempts,
    Value<DateTime>? nextAttemptAt,
    Value<DateTime?>? leaseUntil,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
  }) {
    return OutboxOpsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      conversationId: conversationId ?? this.conversationId,
      messageRowid: messageRowid ?? this.messageRowid,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      payload: payload ?? this.payload,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      leaseUntil: leaseUntil ?? this.leaseUntil,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (messageRowid.present) {
      map['message_rowid'] = Variable<int>(messageRowid.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $OutboxOpsTable.$converterstate.toSql(state.value),
      );
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(
        $OutboxOpsTable.$converternextAttemptAt.toSql(nextAttemptAt.value),
      );
    }
    if (leaseUntil.present) {
      map['lease_until'] = Variable<int>(
        $OutboxOpsTable.$converterleaseUntiln.toSql(leaseUntil.value),
      );
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $OutboxOpsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOpsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('conversationId: $conversationId, ')
          ..write('messageRowid: $messageRowid, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('leaseUntil: $leaseUntil, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DeferredActionsTable extends DeferredActions
    with TableInfo<$DeferredActionsTable, DeferredActionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeferredActionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _targetMessageIdMeta = const VerificationMeta(
    'targetMessageId',
  );
  @override
  late final GeneratedColumn<String> targetMessageId = GeneratedColumn<String>(
    'target_message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetAuthorMeta = const VerificationMeta(
    'targetAuthor',
  );
  @override
  late final GeneratedColumn<String> targetAuthor = GeneratedColumn<String>(
    'target_author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
    'sender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderDeviceMeta = const VerificationMeta(
    'senderDevice',
  );
  @override
  late final GeneratedColumn<String> senderDevice = GeneratedColumn<String>(
    'sender_device',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> receivedAt =
      GeneratedColumn<int>(
        'received_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DeferredActionsTable.$converterreceivedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> expiresAt =
      GeneratedColumn<int>(
        'expires_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DeferredActionsTable.$converterexpiresAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    targetMessageId,
    targetAuthor,
    sender,
    senderDevice,
    kind,
    payload,
    receivedAt,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deferred_actions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeferredActionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('target_message_id')) {
      context.handle(
        _targetMessageIdMeta,
        targetMessageId.isAcceptableOrUnknown(
          data['target_message_id']!,
          _targetMessageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetMessageIdMeta);
    }
    if (data.containsKey('target_author')) {
      context.handle(
        _targetAuthorMeta,
        targetAuthor.isAcceptableOrUnknown(
          data['target_author']!,
          _targetAuthorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetAuthorMeta);
    }
    if (data.containsKey('sender')) {
      context.handle(
        _senderMeta,
        sender.isAcceptableOrUnknown(data['sender']!, _senderMeta),
      );
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('sender_device')) {
      context.handle(
        _senderDeviceMeta,
        senderDevice.isAcceptableOrUnknown(
          data['sender_device']!,
          _senderDeviceMeta,
        ),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeferredActionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeferredActionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      targetMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_message_id'],
      )!,
      targetAuthor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_author'],
      )!,
      sender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender'],
      )!,
      senderDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_device'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      receivedAt: $DeferredActionsTable.$converterreceivedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}received_at'],
        )!,
      ),
      expiresAt: $DeferredActionsTable.$converterexpiresAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}expires_at'],
        )!,
      ),
    );
  }

  @override
  $DeferredActionsTable createAlias(String alias) {
    return $DeferredActionsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterreceivedAt = const EpochMs();
  static TypeConverter<DateTime, int> $converterexpiresAt = const EpochMs();
}

class DeferredActionRow extends DataClass
    implements Insertable<DeferredActionRow> {
  final int id;
  final String targetMessageId;
  final String targetAuthor;
  final String sender;
  final String? senderDevice;

  /// The content `type` of the action.
  final String kind;

  /// The decoded content message as JSON.
  final String payload;
  final DateTime receivedAt;
  final DateTime expiresAt;
  const DeferredActionRow({
    required this.id,
    required this.targetMessageId,
    required this.targetAuthor,
    required this.sender,
    this.senderDevice,
    required this.kind,
    required this.payload,
    required this.receivedAt,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['target_message_id'] = Variable<String>(targetMessageId);
    map['target_author'] = Variable<String>(targetAuthor);
    map['sender'] = Variable<String>(sender);
    if (!nullToAbsent || senderDevice != null) {
      map['sender_device'] = Variable<String>(senderDevice);
    }
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<String>(payload);
    {
      map['received_at'] = Variable<int>(
        $DeferredActionsTable.$converterreceivedAt.toSql(receivedAt),
      );
    }
    {
      map['expires_at'] = Variable<int>(
        $DeferredActionsTable.$converterexpiresAt.toSql(expiresAt),
      );
    }
    return map;
  }

  DeferredActionsCompanion toCompanion(bool nullToAbsent) {
    return DeferredActionsCompanion(
      id: Value(id),
      targetMessageId: Value(targetMessageId),
      targetAuthor: Value(targetAuthor),
      sender: Value(sender),
      senderDevice: senderDevice == null && nullToAbsent
          ? const Value.absent()
          : Value(senderDevice),
      kind: Value(kind),
      payload: Value(payload),
      receivedAt: Value(receivedAt),
      expiresAt: Value(expiresAt),
    );
  }

  factory DeferredActionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeferredActionRow(
      id: serializer.fromJson<int>(json['id']),
      targetMessageId: serializer.fromJson<String>(json['targetMessageId']),
      targetAuthor: serializer.fromJson<String>(json['targetAuthor']),
      sender: serializer.fromJson<String>(json['sender']),
      senderDevice: serializer.fromJson<String?>(json['senderDevice']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<String>(json['payload']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'targetMessageId': serializer.toJson<String>(targetMessageId),
      'targetAuthor': serializer.toJson<String>(targetAuthor),
      'sender': serializer.toJson<String>(sender),
      'senderDevice': serializer.toJson<String?>(senderDevice),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<String>(payload),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
    };
  }

  DeferredActionRow copyWith({
    int? id,
    String? targetMessageId,
    String? targetAuthor,
    String? sender,
    Value<String?> senderDevice = const Value.absent(),
    String? kind,
    String? payload,
    DateTime? receivedAt,
    DateTime? expiresAt,
  }) => DeferredActionRow(
    id: id ?? this.id,
    targetMessageId: targetMessageId ?? this.targetMessageId,
    targetAuthor: targetAuthor ?? this.targetAuthor,
    sender: sender ?? this.sender,
    senderDevice: senderDevice.present ? senderDevice.value : this.senderDevice,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
    receivedAt: receivedAt ?? this.receivedAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  DeferredActionRow copyWithCompanion(DeferredActionsCompanion data) {
    return DeferredActionRow(
      id: data.id.present ? data.id.value : this.id,
      targetMessageId: data.targetMessageId.present
          ? data.targetMessageId.value
          : this.targetMessageId,
      targetAuthor: data.targetAuthor.present
          ? data.targetAuthor.value
          : this.targetAuthor,
      sender: data.sender.present ? data.sender.value : this.sender,
      senderDevice: data.senderDevice.present
          ? data.senderDevice.value
          : this.senderDevice,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeferredActionRow(')
          ..write('id: $id, ')
          ..write('targetMessageId: $targetMessageId, ')
          ..write('targetAuthor: $targetAuthor, ')
          ..write('sender: $sender, ')
          ..write('senderDevice: $senderDevice, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    targetMessageId,
    targetAuthor,
    sender,
    senderDevice,
    kind,
    payload,
    receivedAt,
    expiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeferredActionRow &&
          other.id == this.id &&
          other.targetMessageId == this.targetMessageId &&
          other.targetAuthor == this.targetAuthor &&
          other.sender == this.sender &&
          other.senderDevice == this.senderDevice &&
          other.kind == this.kind &&
          other.payload == this.payload &&
          other.receivedAt == this.receivedAt &&
          other.expiresAt == this.expiresAt);
}

class DeferredActionsCompanion extends UpdateCompanion<DeferredActionRow> {
  final Value<int> id;
  final Value<String> targetMessageId;
  final Value<String> targetAuthor;
  final Value<String> sender;
  final Value<String?> senderDevice;
  final Value<String> kind;
  final Value<String> payload;
  final Value<DateTime> receivedAt;
  final Value<DateTime> expiresAt;
  const DeferredActionsCompanion({
    this.id = const Value.absent(),
    this.targetMessageId = const Value.absent(),
    this.targetAuthor = const Value.absent(),
    this.sender = const Value.absent(),
    this.senderDevice = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
  });
  DeferredActionsCompanion.insert({
    this.id = const Value.absent(),
    required String targetMessageId,
    required String targetAuthor,
    required String sender,
    this.senderDevice = const Value.absent(),
    required String kind,
    required String payload,
    required DateTime receivedAt,
    required DateTime expiresAt,
  }) : targetMessageId = Value(targetMessageId),
       targetAuthor = Value(targetAuthor),
       sender = Value(sender),
       kind = Value(kind),
       payload = Value(payload),
       receivedAt = Value(receivedAt),
       expiresAt = Value(expiresAt);
  static Insertable<DeferredActionRow> custom({
    Expression<int>? id,
    Expression<String>? targetMessageId,
    Expression<String>? targetAuthor,
    Expression<String>? sender,
    Expression<String>? senderDevice,
    Expression<String>? kind,
    Expression<String>? payload,
    Expression<int>? receivedAt,
    Expression<int>? expiresAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (targetMessageId != null) 'target_message_id': targetMessageId,
      if (targetAuthor != null) 'target_author': targetAuthor,
      if (sender != null) 'sender': sender,
      if (senderDevice != null) 'sender_device': senderDevice,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (receivedAt != null) 'received_at': receivedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
    });
  }

  DeferredActionsCompanion copyWith({
    Value<int>? id,
    Value<String>? targetMessageId,
    Value<String>? targetAuthor,
    Value<String>? sender,
    Value<String?>? senderDevice,
    Value<String>? kind,
    Value<String>? payload,
    Value<DateTime>? receivedAt,
    Value<DateTime>? expiresAt,
  }) {
    return DeferredActionsCompanion(
      id: id ?? this.id,
      targetMessageId: targetMessageId ?? this.targetMessageId,
      targetAuthor: targetAuthor ?? this.targetAuthor,
      sender: sender ?? this.sender,
      senderDevice: senderDevice ?? this.senderDevice,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      receivedAt: receivedAt ?? this.receivedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (targetMessageId.present) {
      map['target_message_id'] = Variable<String>(targetMessageId.value);
    }
    if (targetAuthor.present) {
      map['target_author'] = Variable<String>(targetAuthor.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (senderDevice.present) {
      map['sender_device'] = Variable<String>(senderDevice.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<int>(
        $DeferredActionsTable.$converterreceivedAt.toSql(receivedAt.value),
      );
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(
        $DeferredActionsTable.$converterexpiresAt.toSql(expiresAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeferredActionsCompanion(')
          ..write('id: $id, ')
          ..write('targetMessageId: $targetMessageId, ')
          ..write('targetAuthor: $targetAuthor, ')
          ..write('sender: $sender, ')
          ..write('senderDevice: $senderDevice, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }
}

class $TransferJobsTable extends TransferJobs
    with TableInfo<$TransferJobsTable, TransferRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransferJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attachmentRowidMeta = const VerificationMeta(
    'attachmentRowid',
  );
  @override
  late final GeneratedColumn<int> attachmentRowid = GeneratedColumn<int>(
    'attachment_rowid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attachments (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _offsetMeta = const VerificationMeta('offset');
  @override
  late final GeneratedColumn<int> offset = GeneratedColumn<int>(
    'offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mediaKeyMeta = const VerificationMeta(
    'mediaKey',
  );
  @override
  late final GeneratedColumn<Uint8List> mediaKey = GeneratedColumn<Uint8List>(
    'media_key',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _purposeMeta = const VerificationMeta(
    'purpose',
  );
  @override
  late final GeneratedColumn<String> purpose = GeneratedColumn<String>(
    'purpose',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TransferState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TransferState>($TransferJobsTable.$converterstate);
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> nextAttemptAt =
      GeneratedColumn<int>(
        'next_attempt_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TransferJobsTable.$converternextAttemptAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> leaseUntil =
      GeneratedColumn<int>(
        'lease_until',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TransferJobsTable.$converterleaseUntiln);
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TransferJobsTable.$convertercreatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    attachmentRowid,
    mediaId,
    localPath,
    size,
    offset,
    mediaKey,
    purpose,
    state,
    attempts,
    nextAttemptAt,
    leaseUntil,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfer_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('attachment_rowid')) {
      context.handle(
        _attachmentRowidMeta,
        attachmentRowid.isAcceptableOrUnknown(
          data['attachment_rowid']!,
          _attachmentRowidMeta,
        ),
      );
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('offset')) {
      context.handle(
        _offsetMeta,
        offset.isAcceptableOrUnknown(data['offset']!, _offsetMeta),
      );
    }
    if (data.containsKey('media_key')) {
      context.handle(
        _mediaKeyMeta,
        mediaKey.isAcceptableOrUnknown(data['media_key']!, _mediaKeyMeta),
      );
    }
    if (data.containsKey('purpose')) {
      context.handle(
        _purposeMeta,
        purpose.isAcceptableOrUnknown(data['purpose']!, _purposeMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {attachmentRowid},
  ];
  @override
  TransferRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      attachmentRowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attachment_rowid'],
      ),
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      offset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset'],
      )!,
      mediaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}media_key'],
      ),
      purpose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purpose'],
      ),
      state: $TransferJobsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: $TransferJobsTable.$converternextAttemptAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}next_attempt_at'],
        )!,
      ),
      leaseUntil: $TransferJobsTable.$converterleaseUntiln.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}lease_until'],
        ),
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: $TransferJobsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
    );
  }

  @override
  $TransferJobsTable createAlias(String alias) {
    return $TransferJobsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TransferState, String, String> $converterstate =
      const EnumNameConverter<TransferState>(TransferState.values);
  static TypeConverter<DateTime, int> $converternextAttemptAt = const EpochMs();
  static TypeConverter<DateTime, int> $converterleaseUntil = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterleaseUntiln =
      NullAwareTypeConverter.wrap($converterleaseUntil);
  static TypeConverter<DateTime, int> $convertercreatedAt = const EpochMs();
}

class TransferRow extends DataClass implements Insertable<TransferRow> {
  final int id;

  /// `upload`, `download`, `thumbnail` or `delete`.
  final String kind;

  /// The attachment this moves. Null for a standalone transfer (a group
  /// avatar, a backup blob).
  final int? attachmentRowid;

  /// Server object id, once the upload target has been created.
  final String? mediaId;

  /// Where the bytes are, on this device.
  final String? localPath;
  final int size;

  /// How many bytes are already uploaded or downloaded, so a resumed transfer
  /// continues rather than restarting.
  final int offset;

  /// The key that decrypts the object (CRYPTO_V2.md §12), so a resumed
  /// download does not have to re-read the message row.
  final Uint8List? mediaKey;

  /// What this is for when it is not a plain attachment: `history_backup`,
  /// `full_backup`, `group_avatar`.
  final String? purpose;
  final TransferState state;
  final int attempts;
  final DateTime nextAttemptAt;
  final DateTime? leaseUntil;

  /// An error code only, never content.
  final String? lastError;
  final DateTime createdAt;
  const TransferRow({
    required this.id,
    required this.kind,
    this.attachmentRowid,
    this.mediaId,
    this.localPath,
    required this.size,
    required this.offset,
    this.mediaKey,
    this.purpose,
    required this.state,
    required this.attempts,
    required this.nextAttemptAt,
    this.leaseUntil,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || attachmentRowid != null) {
      map['attachment_rowid'] = Variable<int>(attachmentRowid);
    }
    if (!nullToAbsent || mediaId != null) {
      map['media_id'] = Variable<String>(mediaId);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['size'] = Variable<int>(size);
    map['offset'] = Variable<int>(offset);
    if (!nullToAbsent || mediaKey != null) {
      map['media_key'] = Variable<Uint8List>(mediaKey);
    }
    if (!nullToAbsent || purpose != null) {
      map['purpose'] = Variable<String>(purpose);
    }
    {
      map['state'] = Variable<String>(
        $TransferJobsTable.$converterstate.toSql(state),
      );
    }
    map['attempts'] = Variable<int>(attempts);
    {
      map['next_attempt_at'] = Variable<int>(
        $TransferJobsTable.$converternextAttemptAt.toSql(nextAttemptAt),
      );
    }
    if (!nullToAbsent || leaseUntil != null) {
      map['lease_until'] = Variable<int>(
        $TransferJobsTable.$converterleaseUntiln.toSql(leaseUntil),
      );
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    {
      map['created_at'] = Variable<int>(
        $TransferJobsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    return map;
  }

  TransferJobsCompanion toCompanion(bool nullToAbsent) {
    return TransferJobsCompanion(
      id: Value(id),
      kind: Value(kind),
      attachmentRowid: attachmentRowid == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentRowid),
      mediaId: mediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaId),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      size: Value(size),
      offset: Value(offset),
      mediaKey: mediaKey == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaKey),
      purpose: purpose == null && nullToAbsent
          ? const Value.absent()
          : Value(purpose),
      state: Value(state),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      leaseUntil: leaseUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseUntil),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory TransferRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferRow(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      attachmentRowid: serializer.fromJson<int?>(json['attachmentRowid']),
      mediaId: serializer.fromJson<String?>(json['mediaId']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      size: serializer.fromJson<int>(json['size']),
      offset: serializer.fromJson<int>(json['offset']),
      mediaKey: serializer.fromJson<Uint8List?>(json['mediaKey']),
      purpose: serializer.fromJson<String?>(json['purpose']),
      state: $TransferJobsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime>(json['nextAttemptAt']),
      leaseUntil: serializer.fromJson<DateTime?>(json['leaseUntil']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'attachmentRowid': serializer.toJson<int?>(attachmentRowid),
      'mediaId': serializer.toJson<String?>(mediaId),
      'localPath': serializer.toJson<String?>(localPath),
      'size': serializer.toJson<int>(size),
      'offset': serializer.toJson<int>(offset),
      'mediaKey': serializer.toJson<Uint8List?>(mediaKey),
      'purpose': serializer.toJson<String?>(purpose),
      'state': serializer.toJson<String>(
        $TransferJobsTable.$converterstate.toJson(state),
      ),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime>(nextAttemptAt),
      'leaseUntil': serializer.toJson<DateTime?>(leaseUntil),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TransferRow copyWith({
    int? id,
    String? kind,
    Value<int?> attachmentRowid = const Value.absent(),
    Value<String?> mediaId = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    int? size,
    int? offset,
    Value<Uint8List?> mediaKey = const Value.absent(),
    Value<String?> purpose = const Value.absent(),
    TransferState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    Value<DateTime?> leaseUntil = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => TransferRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    attachmentRowid: attachmentRowid.present
        ? attachmentRowid.value
        : this.attachmentRowid,
    mediaId: mediaId.present ? mediaId.value : this.mediaId,
    localPath: localPath.present ? localPath.value : this.localPath,
    size: size ?? this.size,
    offset: offset ?? this.offset,
    mediaKey: mediaKey.present ? mediaKey.value : this.mediaKey,
    purpose: purpose.present ? purpose.value : this.purpose,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    leaseUntil: leaseUntil.present ? leaseUntil.value : this.leaseUntil,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  TransferRow copyWithCompanion(TransferJobsCompanion data) {
    return TransferRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      attachmentRowid: data.attachmentRowid.present
          ? data.attachmentRowid.value
          : this.attachmentRowid,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      size: data.size.present ? data.size.value : this.size,
      offset: data.offset.present ? data.offset.value : this.offset,
      mediaKey: data.mediaKey.present ? data.mediaKey.value : this.mediaKey,
      purpose: data.purpose.present ? data.purpose.value : this.purpose,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      leaseUntil: data.leaseUntil.present
          ? data.leaseUntil.value
          : this.leaseUntil,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('attachmentRowid: $attachmentRowid, ')
          ..write('mediaId: $mediaId, ')
          ..write('localPath: $localPath, ')
          ..write('size: $size, ')
          ..write('offset: $offset, ')
          ..write('mediaKey: $mediaKey, ')
          ..write('purpose: $purpose, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('leaseUntil: $leaseUntil, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    attachmentRowid,
    mediaId,
    localPath,
    size,
    offset,
    $driftBlobEquality.hash(mediaKey),
    purpose,
    state,
    attempts,
    nextAttemptAt,
    leaseUntil,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.attachmentRowid == this.attachmentRowid &&
          other.mediaId == this.mediaId &&
          other.localPath == this.localPath &&
          other.size == this.size &&
          other.offset == this.offset &&
          $driftBlobEquality.equals(other.mediaKey, this.mediaKey) &&
          other.purpose == this.purpose &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.leaseUntil == this.leaseUntil &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class TransferJobsCompanion extends UpdateCompanion<TransferRow> {
  final Value<int> id;
  final Value<String> kind;
  final Value<int?> attachmentRowid;
  final Value<String?> mediaId;
  final Value<String?> localPath;
  final Value<int> size;
  final Value<int> offset;
  final Value<Uint8List?> mediaKey;
  final Value<String?> purpose;
  final Value<TransferState> state;
  final Value<int> attempts;
  final Value<DateTime> nextAttemptAt;
  final Value<DateTime?> leaseUntil;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  const TransferJobsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.attachmentRowid = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.size = const Value.absent(),
    this.offset = const Value.absent(),
    this.mediaKey = const Value.absent(),
    this.purpose = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.leaseUntil = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TransferJobsCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    this.attachmentRowid = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.size = const Value.absent(),
    this.offset = const Value.absent(),
    this.mediaKey = const Value.absent(),
    this.purpose = const Value.absent(),
    required TransferState state,
    this.attempts = const Value.absent(),
    required DateTime nextAttemptAt,
    this.leaseUntil = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
  }) : kind = Value(kind),
       state = Value(state),
       nextAttemptAt = Value(nextAttemptAt),
       createdAt = Value(createdAt);
  static Insertable<TransferRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<int>? attachmentRowid,
    Expression<String>? mediaId,
    Expression<String>? localPath,
    Expression<int>? size,
    Expression<int>? offset,
    Expression<Uint8List>? mediaKey,
    Expression<String>? purpose,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<int>? leaseUntil,
    Expression<String>? lastError,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (attachmentRowid != null) 'attachment_rowid': attachmentRowid,
      if (mediaId != null) 'media_id': mediaId,
      if (localPath != null) 'local_path': localPath,
      if (size != null) 'size': size,
      if (offset != null) 'offset': offset,
      if (mediaKey != null) 'media_key': mediaKey,
      if (purpose != null) 'purpose': purpose,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (leaseUntil != null) 'lease_until': leaseUntil,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TransferJobsCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<int?>? attachmentRowid,
    Value<String?>? mediaId,
    Value<String?>? localPath,
    Value<int>? size,
    Value<int>? offset,
    Value<Uint8List?>? mediaKey,
    Value<String?>? purpose,
    Value<TransferState>? state,
    Value<int>? attempts,
    Value<DateTime>? nextAttemptAt,
    Value<DateTime?>? leaseUntil,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
  }) {
    return TransferJobsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      attachmentRowid: attachmentRowid ?? this.attachmentRowid,
      mediaId: mediaId ?? this.mediaId,
      localPath: localPath ?? this.localPath,
      size: size ?? this.size,
      offset: offset ?? this.offset,
      mediaKey: mediaKey ?? this.mediaKey,
      purpose: purpose ?? this.purpose,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      leaseUntil: leaseUntil ?? this.leaseUntil,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (attachmentRowid.present) {
      map['attachment_rowid'] = Variable<int>(attachmentRowid.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (offset.present) {
      map['offset'] = Variable<int>(offset.value);
    }
    if (mediaKey.present) {
      map['media_key'] = Variable<Uint8List>(mediaKey.value);
    }
    if (purpose.present) {
      map['purpose'] = Variable<String>(purpose.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $TransferJobsTable.$converterstate.toSql(state.value),
      );
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(
        $TransferJobsTable.$converternextAttemptAt.toSql(nextAttemptAt.value),
      );
    }
    if (leaseUntil.present) {
      map['lease_until'] = Variable<int>(
        $TransferJobsTable.$converterleaseUntiln.toSql(leaseUntil.value),
      );
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $TransferJobsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransferJobsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('attachmentRowid: $attachmentRowid, ')
          ..write('mediaId: $mediaId, ')
          ..write('localPath: $localPath, ')
          ..write('size: $size, ')
          ..write('offset: $offset, ')
          ..write('mediaKey: $mediaKey, ')
          ..write('purpose: $purpose, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('leaseUntil: $leaseUntil, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TransferChunksTable extends TransferChunks
    with TableInfo<$TransferChunksTable, TransferChunkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransferChunksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _transferIdMeta = const VerificationMeta(
    'transferId',
  );
  @override
  late final GeneratedColumn<String> transferId = GeneratedColumn<String>(
    'transfer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<int> total = GeneratedColumn<int>(
    'total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFinalMeta = const VerificationMeta(
    'isFinal',
  );
  @override
  late final GeneratedColumn<bool> isFinal = GeneratedColumn<bool>(
    'is_final',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_final" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> receivedAt =
      GeneratedColumn<int>(
        'received_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TransferChunksTable.$converterreceivedAt);
  @override
  List<GeneratedColumn> get $columns => [
    transferId,
    sequence,
    payload,
    total,
    isFinal,
    receivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfer_chunks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferChunkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('transfer_id')) {
      context.handle(
        _transferIdMeta,
        transferId.isAcceptableOrUnknown(data['transfer_id']!, _transferIdMeta),
      );
    } else if (isInserting) {
      context.missing(_transferIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('total')) {
      context.handle(
        _totalMeta,
        total.isAcceptableOrUnknown(data['total']!, _totalMeta),
      );
    } else if (isInserting) {
      context.missing(_totalMeta);
    }
    if (data.containsKey('is_final')) {
      context.handle(
        _isFinalMeta,
        isFinal.isAcceptableOrUnknown(data['is_final']!, _isFinalMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {transferId, sequence};
  @override
  TransferChunkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferChunkRow(
      transferId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      )!,
      total: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total'],
      )!,
      isFinal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_final'],
      )!,
      receivedAt: $TransferChunksTable.$converterreceivedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}received_at'],
        )!,
      ),
    );
  }

  @override
  $TransferChunksTable createAlias(String alias) {
    return $TransferChunksTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterreceivedAt = const EpochMs();
}

class TransferChunkRow extends DataClass
    implements Insertable<TransferChunkRow> {
  final String transferId;
  final int sequence;
  final Uint8List payload;

  /// Total chunks, so a gap is detectable rather than silently accepted.
  final int total;
  final bool isFinal;
  final DateTime receivedAt;
  const TransferChunkRow({
    required this.transferId,
    required this.sequence,
    required this.payload,
    required this.total,
    required this.isFinal,
    required this.receivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['transfer_id'] = Variable<String>(transferId);
    map['sequence'] = Variable<int>(sequence);
    map['payload'] = Variable<Uint8List>(payload);
    map['total'] = Variable<int>(total);
    map['is_final'] = Variable<bool>(isFinal);
    {
      map['received_at'] = Variable<int>(
        $TransferChunksTable.$converterreceivedAt.toSql(receivedAt),
      );
    }
    return map;
  }

  TransferChunksCompanion toCompanion(bool nullToAbsent) {
    return TransferChunksCompanion(
      transferId: Value(transferId),
      sequence: Value(sequence),
      payload: Value(payload),
      total: Value(total),
      isFinal: Value(isFinal),
      receivedAt: Value(receivedAt),
    );
  }

  factory TransferChunkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferChunkRow(
      transferId: serializer.fromJson<String>(json['transferId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      total: serializer.fromJson<int>(json['total']),
      isFinal: serializer.fromJson<bool>(json['isFinal']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'transferId': serializer.toJson<String>(transferId),
      'sequence': serializer.toJson<int>(sequence),
      'payload': serializer.toJson<Uint8List>(payload),
      'total': serializer.toJson<int>(total),
      'isFinal': serializer.toJson<bool>(isFinal),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
    };
  }

  TransferChunkRow copyWith({
    String? transferId,
    int? sequence,
    Uint8List? payload,
    int? total,
    bool? isFinal,
    DateTime? receivedAt,
  }) => TransferChunkRow(
    transferId: transferId ?? this.transferId,
    sequence: sequence ?? this.sequence,
    payload: payload ?? this.payload,
    total: total ?? this.total,
    isFinal: isFinal ?? this.isFinal,
    receivedAt: receivedAt ?? this.receivedAt,
  );
  TransferChunkRow copyWithCompanion(TransferChunksCompanion data) {
    return TransferChunkRow(
      transferId: data.transferId.present
          ? data.transferId.value
          : this.transferId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      payload: data.payload.present ? data.payload.value : this.payload,
      total: data.total.present ? data.total.value : this.total,
      isFinal: data.isFinal.present ? data.isFinal.value : this.isFinal,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferChunkRow(')
          ..write('transferId: $transferId, ')
          ..write('sequence: $sequence, ')
          ..write('payload: $payload, ')
          ..write('total: $total, ')
          ..write('isFinal: $isFinal, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    transferId,
    sequence,
    $driftBlobEquality.hash(payload),
    total,
    isFinal,
    receivedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferChunkRow &&
          other.transferId == this.transferId &&
          other.sequence == this.sequence &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.total == this.total &&
          other.isFinal == this.isFinal &&
          other.receivedAt == this.receivedAt);
}

class TransferChunksCompanion extends UpdateCompanion<TransferChunkRow> {
  final Value<String> transferId;
  final Value<int> sequence;
  final Value<Uint8List> payload;
  final Value<int> total;
  final Value<bool> isFinal;
  final Value<DateTime> receivedAt;
  final Value<int> rowid;
  const TransferChunksCompanion({
    this.transferId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.payload = const Value.absent(),
    this.total = const Value.absent(),
    this.isFinal = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransferChunksCompanion.insert({
    required String transferId,
    required int sequence,
    required Uint8List payload,
    required int total,
    this.isFinal = const Value.absent(),
    required DateTime receivedAt,
    this.rowid = const Value.absent(),
  }) : transferId = Value(transferId),
       sequence = Value(sequence),
       payload = Value(payload),
       total = Value(total),
       receivedAt = Value(receivedAt);
  static Insertable<TransferChunkRow> custom({
    Expression<String>? transferId,
    Expression<int>? sequence,
    Expression<Uint8List>? payload,
    Expression<int>? total,
    Expression<bool>? isFinal,
    Expression<int>? receivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (transferId != null) 'transfer_id': transferId,
      if (sequence != null) 'sequence': sequence,
      if (payload != null) 'payload': payload,
      if (total != null) 'total': total,
      if (isFinal != null) 'is_final': isFinal,
      if (receivedAt != null) 'received_at': receivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransferChunksCompanion copyWith({
    Value<String>? transferId,
    Value<int>? sequence,
    Value<Uint8List>? payload,
    Value<int>? total,
    Value<bool>? isFinal,
    Value<DateTime>? receivedAt,
    Value<int>? rowid,
  }) {
    return TransferChunksCompanion(
      transferId: transferId ?? this.transferId,
      sequence: sequence ?? this.sequence,
      payload: payload ?? this.payload,
      total: total ?? this.total,
      isFinal: isFinal ?? this.isFinal,
      receivedAt: receivedAt ?? this.receivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (transferId.present) {
      map['transfer_id'] = Variable<String>(transferId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (total.present) {
      map['total'] = Variable<int>(total.value);
    }
    if (isFinal.present) {
      map['is_final'] = Variable<bool>(isFinal.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<int>(
        $TransferChunksTable.$converterreceivedAt.toSql(receivedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransferChunksCompanion(')
          ..write('transferId: $transferId, ')
          ..write('sequence: $sequence, ')
          ..write('payload: $payload, ')
          ..write('total: $total, ')
          ..write('isFinal: $isFinal, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupsTable extends Groups with TableInfo<$GroupsTable, GroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<Uint8List> avatar = GeneratedColumn<Uint8List>(
    'avatar',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<int> epoch = GeneratedColumn<int>(
    'epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<Uint8List> state = GeneratedColumn<Uint8List>(
    'state',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateVersionMeta = const VerificationMeta(
    'stateVersion',
  );
  @override
  late final GeneratedColumn<int> stateVersion = GeneratedColumn<int>(
    'state_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _mutedMeta = const VerificationMeta('muted');
  @override
  late final GeneratedColumn<bool> muted = GeneratedColumn<bool>(
    'muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("muted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastMessageRowidMeta = const VerificationMeta(
    'lastMessageRowid',
  );
  @override
  late final GeneratedColumn<int> lastMessageRowid = GeneratedColumn<int>(
    'last_message_rowid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageSortKeyMeta =
      const VerificationMeta('lastMessageSortKey');
  @override
  late final GeneratedColumn<String> lastMessageSortKey =
      GeneratedColumn<String>(
        'last_message_sort_key',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastMessageAt =
      GeneratedColumn<int>(
        'last_message_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($GroupsTable.$converterlastMessageAtn);
  static const VerificationMeta _lastMessagePreviewMeta =
      const VerificationMeta('lastMessagePreview');
  @override
  late final GeneratedColumn<String> lastMessagePreview =
      GeneratedColumn<String>(
        'last_message_preview',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mentionCountMeta = const VerificationMeta(
    'mentionCount',
  );
  @override
  late final GeneratedColumn<int> mentionCount = GeneratedColumn<int>(
    'mention_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($GroupsTable.$convertercreatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    avatar,
    role,
    epoch,
    state,
    stateVersion,
    archived,
    muted,
    lastMessageRowid,
    lastMessageSortKey,
    lastMessageAt,
    lastMessagePreview,
    unreadCount,
    mentionCount,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('epoch')) {
      context.handle(
        _epochMeta,
        epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('state_version')) {
      context.handle(
        _stateVersionMeta,
        stateVersion.isAcceptableOrUnknown(
          data['state_version']!,
          _stateVersionMeta,
        ),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('muted')) {
      context.handle(
        _mutedMeta,
        muted.isAcceptableOrUnknown(data['muted']!, _mutedMeta),
      );
    }
    if (data.containsKey('last_message_rowid')) {
      context.handle(
        _lastMessageRowidMeta,
        lastMessageRowid.isAcceptableOrUnknown(
          data['last_message_rowid']!,
          _lastMessageRowidMeta,
        ),
      );
    }
    if (data.containsKey('last_message_sort_key')) {
      context.handle(
        _lastMessageSortKeyMeta,
        lastMessageSortKey.isAcceptableOrUnknown(
          data['last_message_sort_key']!,
          _lastMessageSortKeyMeta,
        ),
      );
    }
    if (data.containsKey('last_message_preview')) {
      context.handle(
        _lastMessagePreviewMeta,
        lastMessagePreview.isAcceptableOrUnknown(
          data['last_message_preview']!,
          _lastMessagePreviewMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('mention_count')) {
      context.handle(
        _mentionCountMeta,
        mentionCount.isAcceptableOrUnknown(
          data['mention_count']!,
          _mentionCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}avatar'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      epoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epoch'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}state'],
      ),
      stateVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}state_version'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      muted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}muted'],
      )!,
      lastMessageRowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_message_rowid'],
      ),
      lastMessageSortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_sort_key'],
      ),
      lastMessageAt: $GroupsTable.$converterlastMessageAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_message_at'],
        ),
      ),
      lastMessagePreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_preview'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      mentionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mention_count'],
      )!,
      createdAt: $GroupsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
    );
  }

  @override
  $GroupsTable createAlias(String alias) {
    return $GroupsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterlastMessageAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterlastMessageAtn =
      NullAwareTypeConverter.wrap($converterlastMessageAt);
  static TypeConverter<DateTime, int> $convertercreatedAt = const EpochMs();
}

class GroupRow extends DataClass implements Insertable<GroupRow> {
  final String id;
  final String title;
  final Uint8List? avatar;

  /// `GroupRole` wire name (`owner`, `admin`, `member`).
  final String role;

  /// The server's monotonic roster version. A send presenting an older roster
  /// is refused (`device_list_stale`), so it is stored and compared.
  final int epoch;

  /// The group's encrypted state blob and its version.
  final Uint8List? state;
  final int stateVersion;
  final bool archived;
  final bool muted;

  /// `messages.local_rowid` of the newest message, kept as with a direct chat
  /// so the chat list reads one table.
  final int? lastMessageRowid;
  final String? lastMessageSortKey;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadCount;
  final int mentionCount;
  final DateTime createdAt;
  const GroupRow({
    required this.id,
    required this.title,
    this.avatar,
    required this.role,
    required this.epoch,
    this.state,
    required this.stateVersion,
    required this.archived,
    required this.muted,
    this.lastMessageRowid,
    this.lastMessageSortKey,
    this.lastMessageAt,
    this.lastMessagePreview,
    required this.unreadCount,
    required this.mentionCount,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || avatar != null) {
      map['avatar'] = Variable<Uint8List>(avatar);
    }
    map['role'] = Variable<String>(role);
    map['epoch'] = Variable<int>(epoch);
    if (!nullToAbsent || state != null) {
      map['state'] = Variable<Uint8List>(state);
    }
    map['state_version'] = Variable<int>(stateVersion);
    map['archived'] = Variable<bool>(archived);
    map['muted'] = Variable<bool>(muted);
    if (!nullToAbsent || lastMessageRowid != null) {
      map['last_message_rowid'] = Variable<int>(lastMessageRowid);
    }
    if (!nullToAbsent || lastMessageSortKey != null) {
      map['last_message_sort_key'] = Variable<String>(lastMessageSortKey);
    }
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<int>(
        $GroupsTable.$converterlastMessageAtn.toSql(lastMessageAt),
      );
    }
    if (!nullToAbsent || lastMessagePreview != null) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['mention_count'] = Variable<int>(mentionCount);
    {
      map['created_at'] = Variable<int>(
        $GroupsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    return map;
  }

  GroupsCompanion toCompanion(bool nullToAbsent) {
    return GroupsCompanion(
      id: Value(id),
      title: Value(title),
      avatar: avatar == null && nullToAbsent
          ? const Value.absent()
          : Value(avatar),
      role: Value(role),
      epoch: Value(epoch),
      state: state == null && nullToAbsent
          ? const Value.absent()
          : Value(state),
      stateVersion: Value(stateVersion),
      archived: Value(archived),
      muted: Value(muted),
      lastMessageRowid: lastMessageRowid == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageRowid),
      lastMessageSortKey: lastMessageSortKey == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageSortKey),
      lastMessageAt: lastMessageAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageAt),
      lastMessagePreview: lastMessagePreview == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessagePreview),
      unreadCount: Value(unreadCount),
      mentionCount: Value(mentionCount),
      createdAt: Value(createdAt),
    );
  }

  factory GroupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      avatar: serializer.fromJson<Uint8List?>(json['avatar']),
      role: serializer.fromJson<String>(json['role']),
      epoch: serializer.fromJson<int>(json['epoch']),
      state: serializer.fromJson<Uint8List?>(json['state']),
      stateVersion: serializer.fromJson<int>(json['stateVersion']),
      archived: serializer.fromJson<bool>(json['archived']),
      muted: serializer.fromJson<bool>(json['muted']),
      lastMessageRowid: serializer.fromJson<int?>(json['lastMessageRowid']),
      lastMessageSortKey: serializer.fromJson<String?>(
        json['lastMessageSortKey'],
      ),
      lastMessageAt: serializer.fromJson<DateTime?>(json['lastMessageAt']),
      lastMessagePreview: serializer.fromJson<String?>(
        json['lastMessagePreview'],
      ),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      mentionCount: serializer.fromJson<int>(json['mentionCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'avatar': serializer.toJson<Uint8List?>(avatar),
      'role': serializer.toJson<String>(role),
      'epoch': serializer.toJson<int>(epoch),
      'state': serializer.toJson<Uint8List?>(state),
      'stateVersion': serializer.toJson<int>(stateVersion),
      'archived': serializer.toJson<bool>(archived),
      'muted': serializer.toJson<bool>(muted),
      'lastMessageRowid': serializer.toJson<int?>(lastMessageRowid),
      'lastMessageSortKey': serializer.toJson<String?>(lastMessageSortKey),
      'lastMessageAt': serializer.toJson<DateTime?>(lastMessageAt),
      'lastMessagePreview': serializer.toJson<String?>(lastMessagePreview),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'mentionCount': serializer.toJson<int>(mentionCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  GroupRow copyWith({
    String? id,
    String? title,
    Value<Uint8List?> avatar = const Value.absent(),
    String? role,
    int? epoch,
    Value<Uint8List?> state = const Value.absent(),
    int? stateVersion,
    bool? archived,
    bool? muted,
    Value<int?> lastMessageRowid = const Value.absent(),
    Value<String?> lastMessageSortKey = const Value.absent(),
    Value<DateTime?> lastMessageAt = const Value.absent(),
    Value<String?> lastMessagePreview = const Value.absent(),
    int? unreadCount,
    int? mentionCount,
    DateTime? createdAt,
  }) => GroupRow(
    id: id ?? this.id,
    title: title ?? this.title,
    avatar: avatar.present ? avatar.value : this.avatar,
    role: role ?? this.role,
    epoch: epoch ?? this.epoch,
    state: state.present ? state.value : this.state,
    stateVersion: stateVersion ?? this.stateVersion,
    archived: archived ?? this.archived,
    muted: muted ?? this.muted,
    lastMessageRowid: lastMessageRowid.present
        ? lastMessageRowid.value
        : this.lastMessageRowid,
    lastMessageSortKey: lastMessageSortKey.present
        ? lastMessageSortKey.value
        : this.lastMessageSortKey,
    lastMessageAt: lastMessageAt.present
        ? lastMessageAt.value
        : this.lastMessageAt,
    lastMessagePreview: lastMessagePreview.present
        ? lastMessagePreview.value
        : this.lastMessagePreview,
    unreadCount: unreadCount ?? this.unreadCount,
    mentionCount: mentionCount ?? this.mentionCount,
    createdAt: createdAt ?? this.createdAt,
  );
  GroupRow copyWithCompanion(GroupsCompanion data) {
    return GroupRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      role: data.role.present ? data.role.value : this.role,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
      state: data.state.present ? data.state.value : this.state,
      stateVersion: data.stateVersion.present
          ? data.stateVersion.value
          : this.stateVersion,
      archived: data.archived.present ? data.archived.value : this.archived,
      muted: data.muted.present ? data.muted.value : this.muted,
      lastMessageRowid: data.lastMessageRowid.present
          ? data.lastMessageRowid.value
          : this.lastMessageRowid,
      lastMessageSortKey: data.lastMessageSortKey.present
          ? data.lastMessageSortKey.value
          : this.lastMessageSortKey,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      lastMessagePreview: data.lastMessagePreview.present
          ? data.lastMessagePreview.value
          : this.lastMessagePreview,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      mentionCount: data.mentionCount.present
          ? data.mentionCount.value
          : this.mentionCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('avatar: $avatar, ')
          ..write('role: $role, ')
          ..write('epoch: $epoch, ')
          ..write('state: $state, ')
          ..write('stateVersion: $stateVersion, ')
          ..write('archived: $archived, ')
          ..write('muted: $muted, ')
          ..write('lastMessageRowid: $lastMessageRowid, ')
          ..write('lastMessageSortKey: $lastMessageSortKey, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('mentionCount: $mentionCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    $driftBlobEquality.hash(avatar),
    role,
    epoch,
    $driftBlobEquality.hash(state),
    stateVersion,
    archived,
    muted,
    lastMessageRowid,
    lastMessageSortKey,
    lastMessageAt,
    lastMessagePreview,
    unreadCount,
    mentionCount,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupRow &&
          other.id == this.id &&
          other.title == this.title &&
          $driftBlobEquality.equals(other.avatar, this.avatar) &&
          other.role == this.role &&
          other.epoch == this.epoch &&
          $driftBlobEquality.equals(other.state, this.state) &&
          other.stateVersion == this.stateVersion &&
          other.archived == this.archived &&
          other.muted == this.muted &&
          other.lastMessageRowid == this.lastMessageRowid &&
          other.lastMessageSortKey == this.lastMessageSortKey &&
          other.lastMessageAt == this.lastMessageAt &&
          other.lastMessagePreview == this.lastMessagePreview &&
          other.unreadCount == this.unreadCount &&
          other.mentionCount == this.mentionCount &&
          other.createdAt == this.createdAt);
}

class GroupsCompanion extends UpdateCompanion<GroupRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<Uint8List?> avatar;
  final Value<String> role;
  final Value<int> epoch;
  final Value<Uint8List?> state;
  final Value<int> stateVersion;
  final Value<bool> archived;
  final Value<bool> muted;
  final Value<int?> lastMessageRowid;
  final Value<String?> lastMessageSortKey;
  final Value<DateTime?> lastMessageAt;
  final Value<String?> lastMessagePreview;
  final Value<int> unreadCount;
  final Value<int> mentionCount;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const GroupsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.avatar = const Value.absent(),
    this.role = const Value.absent(),
    this.epoch = const Value.absent(),
    this.state = const Value.absent(),
    this.stateVersion = const Value.absent(),
    this.archived = const Value.absent(),
    this.muted = const Value.absent(),
    this.lastMessageRowid = const Value.absent(),
    this.lastMessageSortKey = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.mentionCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupsCompanion.insert({
    required String id,
    required String title,
    this.avatar = const Value.absent(),
    required String role,
    this.epoch = const Value.absent(),
    this.state = const Value.absent(),
    this.stateVersion = const Value.absent(),
    this.archived = const Value.absent(),
    this.muted = const Value.absent(),
    this.lastMessageRowid = const Value.absent(),
    this.lastMessageSortKey = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.mentionCount = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       role = Value(role),
       createdAt = Value(createdAt);
  static Insertable<GroupRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<Uint8List>? avatar,
    Expression<String>? role,
    Expression<int>? epoch,
    Expression<Uint8List>? state,
    Expression<int>? stateVersion,
    Expression<bool>? archived,
    Expression<bool>? muted,
    Expression<int>? lastMessageRowid,
    Expression<String>? lastMessageSortKey,
    Expression<int>? lastMessageAt,
    Expression<String>? lastMessagePreview,
    Expression<int>? unreadCount,
    Expression<int>? mentionCount,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (avatar != null) 'avatar': avatar,
      if (role != null) 'role': role,
      if (epoch != null) 'epoch': epoch,
      if (state != null) 'state': state,
      if (stateVersion != null) 'state_version': stateVersion,
      if (archived != null) 'archived': archived,
      if (muted != null) 'muted': muted,
      if (lastMessageRowid != null) 'last_message_rowid': lastMessageRowid,
      if (lastMessageSortKey != null)
        'last_message_sort_key': lastMessageSortKey,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (lastMessagePreview != null)
        'last_message_preview': lastMessagePreview,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (mentionCount != null) 'mention_count': mentionCount,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<Uint8List?>? avatar,
    Value<String>? role,
    Value<int>? epoch,
    Value<Uint8List?>? state,
    Value<int>? stateVersion,
    Value<bool>? archived,
    Value<bool>? muted,
    Value<int?>? lastMessageRowid,
    Value<String?>? lastMessageSortKey,
    Value<DateTime?>? lastMessageAt,
    Value<String?>? lastMessagePreview,
    Value<int>? unreadCount,
    Value<int>? mentionCount,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return GroupsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      avatar: avatar ?? this.avatar,
      role: role ?? this.role,
      epoch: epoch ?? this.epoch,
      state: state ?? this.state,
      stateVersion: stateVersion ?? this.stateVersion,
      archived: archived ?? this.archived,
      muted: muted ?? this.muted,
      lastMessageRowid: lastMessageRowid ?? this.lastMessageRowid,
      lastMessageSortKey: lastMessageSortKey ?? this.lastMessageSortKey,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      mentionCount: mentionCount ?? this.mentionCount,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<Uint8List>(avatar.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (epoch.present) {
      map['epoch'] = Variable<int>(epoch.value);
    }
    if (state.present) {
      map['state'] = Variable<Uint8List>(state.value);
    }
    if (stateVersion.present) {
      map['state_version'] = Variable<int>(stateVersion.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (muted.present) {
      map['muted'] = Variable<bool>(muted.value);
    }
    if (lastMessageRowid.present) {
      map['last_message_rowid'] = Variable<int>(lastMessageRowid.value);
    }
    if (lastMessageSortKey.present) {
      map['last_message_sort_key'] = Variable<String>(lastMessageSortKey.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<int>(
        $GroupsTable.$converterlastMessageAtn.toSql(lastMessageAt.value),
      );
    }
    if (lastMessagePreview.present) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (mentionCount.present) {
      map['mention_count'] = Variable<int>(mentionCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $GroupsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('avatar: $avatar, ')
          ..write('role: $role, ')
          ..write('epoch: $epoch, ')
          ..write('state: $state, ')
          ..write('stateVersion: $stateVersion, ')
          ..write('archived: $archived, ')
          ..write('muted: $muted, ')
          ..write('lastMessageRowid: $lastMessageRowid, ')
          ..write('lastMessageSortKey: $lastMessageSortKey, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('mentionCount: $mentionCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupMembersTable extends GroupMembers
    with TableInfo<$GroupMembersTable, GroupMemberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES "groups" (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualifiedIdMeta = const VerificationMeta(
    'qualifiedId',
  );
  @override
  late final GeneratedColumn<String> qualifiedId = GeneratedColumn<String>(
    'qualified_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isSelfMeta = const VerificationMeta('isSelf');
  @override
  late final GeneratedColumn<bool> isSelf = GeneratedColumn<bool>(
    'is_self',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_self" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _devicesJsonMeta = const VerificationMeta(
    'devicesJson',
  );
  @override
  late final GeneratedColumn<String> devicesJson = GeneratedColumn<String>(
    'devices_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> devicesFetchedAt =
      GeneratedColumn<int>(
        'devices_fetched_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>(
        $GroupMembersTable.$converterdevicesFetchedAtn,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> joinedAt =
      GeneratedColumn<int>(
        'joined_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($GroupMembersTable.$converterjoinedAtn);
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    accountId,
    qualifiedId,
    displayName,
    role,
    isSelf,
    devicesJson,
    devicesFetchedAt,
    joinedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupMemberRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('qualified_id')) {
      context.handle(
        _qualifiedIdMeta,
        qualifiedId.isAcceptableOrUnknown(
          data['qualified_id']!,
          _qualifiedIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_qualifiedIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('is_self')) {
      context.handle(
        _isSelfMeta,
        isSelf.isAcceptableOrUnknown(data['is_self']!, _isSelfMeta),
      );
    }
    if (data.containsKey('devices_json')) {
      context.handle(
        _devicesJsonMeta,
        devicesJson.isAcceptableOrUnknown(
          data['devices_json']!,
          _devicesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_devicesJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, accountId};
  @override
  GroupMemberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupMemberRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      qualifiedId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}qualified_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      isSelf: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_self'],
      )!,
      devicesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}devices_json'],
      )!,
      devicesFetchedAt: $GroupMembersTable.$converterdevicesFetchedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}devices_fetched_at'],
        ),
      ),
      joinedAt: $GroupMembersTable.$converterjoinedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}joined_at'],
        ),
      ),
    );
  }

  @override
  $GroupMembersTable createAlias(String alias) {
    return $GroupMembersTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterdevicesFetchedAt =
      const EpochMs();
  static TypeConverter<DateTime?, int?> $converterdevicesFetchedAtn =
      NullAwareTypeConverter.wrap($converterdevicesFetchedAt);
  static TypeConverter<DateTime, int> $converterjoinedAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterjoinedAtn =
      NullAwareTypeConverter.wrap($converterjoinedAt);
}

class GroupMemberRow extends DataClass implements Insertable<GroupMemberRow> {
  final String groupId;
  final String accountId;

  /// `uuid@domain` for a member on another server (federation, S6c).
  final String qualifiedId;
  final String? displayName;

  /// `GroupRole` wire name.
  final String role;
  final bool isSelf;

  /// The server's device list for this member, as JSON. Compared by digest, so
  /// a stale send can be detected without this device learning anything about
  /// anybody's devices beyond their ids.
  final String devicesJson;
  final DateTime? devicesFetchedAt;
  final DateTime? joinedAt;
  const GroupMemberRow({
    required this.groupId,
    required this.accountId,
    required this.qualifiedId,
    this.displayName,
    required this.role,
    required this.isSelf,
    required this.devicesJson,
    this.devicesFetchedAt,
    this.joinedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['account_id'] = Variable<String>(accountId);
    map['qualified_id'] = Variable<String>(qualifiedId);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['role'] = Variable<String>(role);
    map['is_self'] = Variable<bool>(isSelf);
    map['devices_json'] = Variable<String>(devicesJson);
    if (!nullToAbsent || devicesFetchedAt != null) {
      map['devices_fetched_at'] = Variable<int>(
        $GroupMembersTable.$converterdevicesFetchedAtn.toSql(devicesFetchedAt),
      );
    }
    if (!nullToAbsent || joinedAt != null) {
      map['joined_at'] = Variable<int>(
        $GroupMembersTable.$converterjoinedAtn.toSql(joinedAt),
      );
    }
    return map;
  }

  GroupMembersCompanion toCompanion(bool nullToAbsent) {
    return GroupMembersCompanion(
      groupId: Value(groupId),
      accountId: Value(accountId),
      qualifiedId: Value(qualifiedId),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      role: Value(role),
      isSelf: Value(isSelf),
      devicesJson: Value(devicesJson),
      devicesFetchedAt: devicesFetchedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(devicesFetchedAt),
      joinedAt: joinedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(joinedAt),
    );
  }

  factory GroupMemberRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupMemberRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      qualifiedId: serializer.fromJson<String>(json['qualifiedId']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      role: serializer.fromJson<String>(json['role']),
      isSelf: serializer.fromJson<bool>(json['isSelf']),
      devicesJson: serializer.fromJson<String>(json['devicesJson']),
      devicesFetchedAt: serializer.fromJson<DateTime?>(
        json['devicesFetchedAt'],
      ),
      joinedAt: serializer.fromJson<DateTime?>(json['joinedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'accountId': serializer.toJson<String>(accountId),
      'qualifiedId': serializer.toJson<String>(qualifiedId),
      'displayName': serializer.toJson<String?>(displayName),
      'role': serializer.toJson<String>(role),
      'isSelf': serializer.toJson<bool>(isSelf),
      'devicesJson': serializer.toJson<String>(devicesJson),
      'devicesFetchedAt': serializer.toJson<DateTime?>(devicesFetchedAt),
      'joinedAt': serializer.toJson<DateTime?>(joinedAt),
    };
  }

  GroupMemberRow copyWith({
    String? groupId,
    String? accountId,
    String? qualifiedId,
    Value<String?> displayName = const Value.absent(),
    String? role,
    bool? isSelf,
    String? devicesJson,
    Value<DateTime?> devicesFetchedAt = const Value.absent(),
    Value<DateTime?> joinedAt = const Value.absent(),
  }) => GroupMemberRow(
    groupId: groupId ?? this.groupId,
    accountId: accountId ?? this.accountId,
    qualifiedId: qualifiedId ?? this.qualifiedId,
    displayName: displayName.present ? displayName.value : this.displayName,
    role: role ?? this.role,
    isSelf: isSelf ?? this.isSelf,
    devicesJson: devicesJson ?? this.devicesJson,
    devicesFetchedAt: devicesFetchedAt.present
        ? devicesFetchedAt.value
        : this.devicesFetchedAt,
    joinedAt: joinedAt.present ? joinedAt.value : this.joinedAt,
  );
  GroupMemberRow copyWithCompanion(GroupMembersCompanion data) {
    return GroupMemberRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      qualifiedId: data.qualifiedId.present
          ? data.qualifiedId.value
          : this.qualifiedId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      role: data.role.present ? data.role.value : this.role,
      isSelf: data.isSelf.present ? data.isSelf.value : this.isSelf,
      devicesJson: data.devicesJson.present
          ? data.devicesJson.value
          : this.devicesJson,
      devicesFetchedAt: data.devicesFetchedAt.present
          ? data.devicesFetchedAt.value
          : this.devicesFetchedAt,
      joinedAt: data.joinedAt.present ? data.joinedAt.value : this.joinedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupMemberRow(')
          ..write('groupId: $groupId, ')
          ..write('accountId: $accountId, ')
          ..write('qualifiedId: $qualifiedId, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('isSelf: $isSelf, ')
          ..write('devicesJson: $devicesJson, ')
          ..write('devicesFetchedAt: $devicesFetchedAt, ')
          ..write('joinedAt: $joinedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    accountId,
    qualifiedId,
    displayName,
    role,
    isSelf,
    devicesJson,
    devicesFetchedAt,
    joinedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupMemberRow &&
          other.groupId == this.groupId &&
          other.accountId == this.accountId &&
          other.qualifiedId == this.qualifiedId &&
          other.displayName == this.displayName &&
          other.role == this.role &&
          other.isSelf == this.isSelf &&
          other.devicesJson == this.devicesJson &&
          other.devicesFetchedAt == this.devicesFetchedAt &&
          other.joinedAt == this.joinedAt);
}

class GroupMembersCompanion extends UpdateCompanion<GroupMemberRow> {
  final Value<String> groupId;
  final Value<String> accountId;
  final Value<String> qualifiedId;
  final Value<String?> displayName;
  final Value<String> role;
  final Value<bool> isSelf;
  final Value<String> devicesJson;
  final Value<DateTime?> devicesFetchedAt;
  final Value<DateTime?> joinedAt;
  final Value<int> rowid;
  const GroupMembersCompanion({
    this.groupId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.qualifiedId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.role = const Value.absent(),
    this.isSelf = const Value.absent(),
    this.devicesJson = const Value.absent(),
    this.devicesFetchedAt = const Value.absent(),
    this.joinedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupMembersCompanion.insert({
    required String groupId,
    required String accountId,
    required String qualifiedId,
    this.displayName = const Value.absent(),
    required String role,
    this.isSelf = const Value.absent(),
    required String devicesJson,
    this.devicesFetchedAt = const Value.absent(),
    this.joinedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       accountId = Value(accountId),
       qualifiedId = Value(qualifiedId),
       role = Value(role),
       devicesJson = Value(devicesJson);
  static Insertable<GroupMemberRow> custom({
    Expression<String>? groupId,
    Expression<String>? accountId,
    Expression<String>? qualifiedId,
    Expression<String>? displayName,
    Expression<String>? role,
    Expression<bool>? isSelf,
    Expression<String>? devicesJson,
    Expression<int>? devicesFetchedAt,
    Expression<int>? joinedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (accountId != null) 'account_id': accountId,
      if (qualifiedId != null) 'qualified_id': qualifiedId,
      if (displayName != null) 'display_name': displayName,
      if (role != null) 'role': role,
      if (isSelf != null) 'is_self': isSelf,
      if (devicesJson != null) 'devices_json': devicesJson,
      if (devicesFetchedAt != null) 'devices_fetched_at': devicesFetchedAt,
      if (joinedAt != null) 'joined_at': joinedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupMembersCompanion copyWith({
    Value<String>? groupId,
    Value<String>? accountId,
    Value<String>? qualifiedId,
    Value<String?>? displayName,
    Value<String>? role,
    Value<bool>? isSelf,
    Value<String>? devicesJson,
    Value<DateTime?>? devicesFetchedAt,
    Value<DateTime?>? joinedAt,
    Value<int>? rowid,
  }) {
    return GroupMembersCompanion(
      groupId: groupId ?? this.groupId,
      accountId: accountId ?? this.accountId,
      qualifiedId: qualifiedId ?? this.qualifiedId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isSelf: isSelf ?? this.isSelf,
      devicesJson: devicesJson ?? this.devicesJson,
      devicesFetchedAt: devicesFetchedAt ?? this.devicesFetchedAt,
      joinedAt: joinedAt ?? this.joinedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (qualifiedId.present) {
      map['qualified_id'] = Variable<String>(qualifiedId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (isSelf.present) {
      map['is_self'] = Variable<bool>(isSelf.value);
    }
    if (devicesJson.present) {
      map['devices_json'] = Variable<String>(devicesJson.value);
    }
    if (devicesFetchedAt.present) {
      map['devices_fetched_at'] = Variable<int>(
        $GroupMembersTable.$converterdevicesFetchedAtn.toSql(
          devicesFetchedAt.value,
        ),
      );
    }
    if (joinedAt.present) {
      map['joined_at'] = Variable<int>(
        $GroupMembersTable.$converterjoinedAtn.toSql(joinedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupMembersCompanion(')
          ..write('groupId: $groupId, ')
          ..write('accountId: $accountId, ')
          ..write('qualifiedId: $qualifiedId, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('isSelf: $isSelf, ')
          ..write('devicesJson: $devicesJson, ')
          ..write('devicesFetchedAt: $devicesFetchedAt, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupBansTable extends GroupBans
    with TableInfo<$GroupBansTable, GroupBanRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupBansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES "groups" (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> bannedAt =
      GeneratedColumn<int>(
        'banned_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($GroupBansTable.$converterbannedAt);
  @override
  List<GeneratedColumn> get $columns => [groupId, accountId, bannedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_bans';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupBanRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, accountId};
  @override
  GroupBanRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupBanRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      bannedAt: $GroupBansTable.$converterbannedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}banned_at'],
        )!,
      ),
    );
  }

  @override
  $GroupBansTable createAlias(String alias) {
    return $GroupBansTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterbannedAt = const EpochMs();
}

class GroupBanRow extends DataClass implements Insertable<GroupBanRow> {
  final String groupId;
  final String accountId;
  final DateTime bannedAt;
  const GroupBanRow({
    required this.groupId,
    required this.accountId,
    required this.bannedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['account_id'] = Variable<String>(accountId);
    {
      map['banned_at'] = Variable<int>(
        $GroupBansTable.$converterbannedAt.toSql(bannedAt),
      );
    }
    return map;
  }

  GroupBansCompanion toCompanion(bool nullToAbsent) {
    return GroupBansCompanion(
      groupId: Value(groupId),
      accountId: Value(accountId),
      bannedAt: Value(bannedAt),
    );
  }

  factory GroupBanRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupBanRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      bannedAt: serializer.fromJson<DateTime>(json['bannedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'accountId': serializer.toJson<String>(accountId),
      'bannedAt': serializer.toJson<DateTime>(bannedAt),
    };
  }

  GroupBanRow copyWith({
    String? groupId,
    String? accountId,
    DateTime? bannedAt,
  }) => GroupBanRow(
    groupId: groupId ?? this.groupId,
    accountId: accountId ?? this.accountId,
    bannedAt: bannedAt ?? this.bannedAt,
  );
  GroupBanRow copyWithCompanion(GroupBansCompanion data) {
    return GroupBanRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      bannedAt: data.bannedAt.present ? data.bannedAt.value : this.bannedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupBanRow(')
          ..write('groupId: $groupId, ')
          ..write('accountId: $accountId, ')
          ..write('bannedAt: $bannedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(groupId, accountId, bannedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupBanRow &&
          other.groupId == this.groupId &&
          other.accountId == this.accountId &&
          other.bannedAt == this.bannedAt);
}

class GroupBansCompanion extends UpdateCompanion<GroupBanRow> {
  final Value<String> groupId;
  final Value<String> accountId;
  final Value<DateTime> bannedAt;
  final Value<int> rowid;
  const GroupBansCompanion({
    this.groupId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.bannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupBansCompanion.insert({
    required String groupId,
    required String accountId,
    required DateTime bannedAt,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       accountId = Value(accountId),
       bannedAt = Value(bannedAt);
  static Insertable<GroupBanRow> custom({
    Expression<String>? groupId,
    Expression<String>? accountId,
    Expression<int>? bannedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (accountId != null) 'account_id': accountId,
      if (bannedAt != null) 'banned_at': bannedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupBansCompanion copyWith({
    Value<String>? groupId,
    Value<String>? accountId,
    Value<DateTime>? bannedAt,
    Value<int>? rowid,
  }) {
    return GroupBansCompanion(
      groupId: groupId ?? this.groupId,
      accountId: accountId ?? this.accountId,
      bannedAt: bannedAt ?? this.bannedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (bannedAt.present) {
      map['banned_at'] = Variable<int>(
        $GroupBansTable.$converterbannedAt.toSql(bannedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupBansCompanion(')
          ..write('groupId: $groupId, ')
          ..write('accountId: $accountId, ')
          ..write('bannedAt: $bannedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CallLogTable extends CallLog with TableInfo<$CallLogTable, CallLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CallLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _callIdMeta = const VerificationMeta('callId');
  @override
  late final GeneratedColumn<String> callId = GeneratedColumn<String>(
    'call_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerAccountIdMeta = const VerificationMeta(
    'peerAccountId',
  );
  @override
  late final GeneratedColumn<String> peerAccountId = GeneratedColumn<String>(
    'peer_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDisplayNameMeta = const VerificationMeta(
    'peerDisplayName',
  );
  @override
  late final GeneratedColumn<String> peerDisplayName = GeneratedColumn<String>(
    'peer_display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _videoMeta = const VerificationMeta('video');
  @override
  late final GeneratedColumn<bool> video = GeneratedColumn<bool>(
    'video',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("video" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> startedAt =
      GeneratedColumn<int>(
        'started_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($CallLogTable.$converterstartedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> answeredAt =
      GeneratedColumn<int>(
        'answered_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($CallLogTable.$converteransweredAtn);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> endedAt =
      GeneratedColumn<int>(
        'ended_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($CallLogTable.$converterendedAtn);
  @override
  List<GeneratedColumn> get $columns => [
    callId,
    peerAccountId,
    peerDisplayName,
    kind,
    direction,
    video,
    state,
    startedAt,
    answeredAt,
    endedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'call_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<CallLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('call_id')) {
      context.handle(
        _callIdMeta,
        callId.isAcceptableOrUnknown(data['call_id']!, _callIdMeta),
      );
    } else if (isInserting) {
      context.missing(_callIdMeta);
    }
    if (data.containsKey('peer_account_id')) {
      context.handle(
        _peerAccountIdMeta,
        peerAccountId.isAcceptableOrUnknown(
          data['peer_account_id']!,
          _peerAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerAccountIdMeta);
    }
    if (data.containsKey('peer_display_name')) {
      context.handle(
        _peerDisplayNameMeta,
        peerDisplayName.isAcceptableOrUnknown(
          data['peer_display_name']!,
          _peerDisplayNameMeta,
        ),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('video')) {
      context.handle(
        _videoMeta,
        video.isAcceptableOrUnknown(data['video']!, _videoMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {callId};
  @override
  CallLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CallLogRow(
      callId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}call_id'],
      )!,
      peerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_account_id'],
      )!,
      peerDisplayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_display_name'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      video: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}video'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      startedAt: $CallLogTable.$converterstartedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}started_at'],
        )!,
      ),
      answeredAt: $CallLogTable.$converteransweredAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}answered_at'],
        ),
      ),
      endedAt: $CallLogTable.$converterendedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}ended_at'],
        ),
      ),
    );
  }

  @override
  $CallLogTable createAlias(String alias) {
    return $CallLogTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterstartedAt = const EpochMs();
  static TypeConverter<DateTime, int> $converteransweredAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converteransweredAtn =
      NullAwareTypeConverter.wrap($converteransweredAt);
  static TypeConverter<DateTime, int> $converterendedAt = const EpochMs();
  static TypeConverter<DateTime?, int?> $converterendedAtn =
      NullAwareTypeConverter.wrap($converterendedAt);
}

class CallLogRow extends DataClass implements Insertable<CallLogRow> {
  final String callId;
  final String peerAccountId;
  final String? peerDisplayName;

  /// `direct` or `group`. Group calls are deferred from v2 (plan §13), but the
  /// column exists so adding them is a data change, not a redesign.
  final String kind;

  /// `incoming`, `outgoing`, `missed`, `declined`, `failed`.
  final String direction;
  final bool video;

  /// `active`, `ended`, `declined`, `missed`, `cancelled`, `unanswered`.
  final String state;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  const CallLogRow({
    required this.callId,
    required this.peerAccountId,
    this.peerDisplayName,
    required this.kind,
    required this.direction,
    required this.video,
    required this.state,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['call_id'] = Variable<String>(callId);
    map['peer_account_id'] = Variable<String>(peerAccountId);
    if (!nullToAbsent || peerDisplayName != null) {
      map['peer_display_name'] = Variable<String>(peerDisplayName);
    }
    map['kind'] = Variable<String>(kind);
    map['direction'] = Variable<String>(direction);
    map['video'] = Variable<bool>(video);
    map['state'] = Variable<String>(state);
    {
      map['started_at'] = Variable<int>(
        $CallLogTable.$converterstartedAt.toSql(startedAt),
      );
    }
    if (!nullToAbsent || answeredAt != null) {
      map['answered_at'] = Variable<int>(
        $CallLogTable.$converteransweredAtn.toSql(answeredAt),
      );
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(
        $CallLogTable.$converterendedAtn.toSql(endedAt),
      );
    }
    return map;
  }

  CallLogCompanion toCompanion(bool nullToAbsent) {
    return CallLogCompanion(
      callId: Value(callId),
      peerAccountId: Value(peerAccountId),
      peerDisplayName: peerDisplayName == null && nullToAbsent
          ? const Value.absent()
          : Value(peerDisplayName),
      kind: Value(kind),
      direction: Value(direction),
      video: Value(video),
      state: Value(state),
      startedAt: Value(startedAt),
      answeredAt: answeredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(answeredAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
    );
  }

  factory CallLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CallLogRow(
      callId: serializer.fromJson<String>(json['callId']),
      peerAccountId: serializer.fromJson<String>(json['peerAccountId']),
      peerDisplayName: serializer.fromJson<String?>(json['peerDisplayName']),
      kind: serializer.fromJson<String>(json['kind']),
      direction: serializer.fromJson<String>(json['direction']),
      video: serializer.fromJson<bool>(json['video']),
      state: serializer.fromJson<String>(json['state']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      answeredAt: serializer.fromJson<DateTime?>(json['answeredAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'callId': serializer.toJson<String>(callId),
      'peerAccountId': serializer.toJson<String>(peerAccountId),
      'peerDisplayName': serializer.toJson<String?>(peerDisplayName),
      'kind': serializer.toJson<String>(kind),
      'direction': serializer.toJson<String>(direction),
      'video': serializer.toJson<bool>(video),
      'state': serializer.toJson<String>(state),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'answeredAt': serializer.toJson<DateTime?>(answeredAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
    };
  }

  CallLogRow copyWith({
    String? callId,
    String? peerAccountId,
    Value<String?> peerDisplayName = const Value.absent(),
    String? kind,
    String? direction,
    bool? video,
    String? state,
    DateTime? startedAt,
    Value<DateTime?> answeredAt = const Value.absent(),
    Value<DateTime?> endedAt = const Value.absent(),
  }) => CallLogRow(
    callId: callId ?? this.callId,
    peerAccountId: peerAccountId ?? this.peerAccountId,
    peerDisplayName: peerDisplayName.present
        ? peerDisplayName.value
        : this.peerDisplayName,
    kind: kind ?? this.kind,
    direction: direction ?? this.direction,
    video: video ?? this.video,
    state: state ?? this.state,
    startedAt: startedAt ?? this.startedAt,
    answeredAt: answeredAt.present ? answeredAt.value : this.answeredAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
  );
  CallLogRow copyWithCompanion(CallLogCompanion data) {
    return CallLogRow(
      callId: data.callId.present ? data.callId.value : this.callId,
      peerAccountId: data.peerAccountId.present
          ? data.peerAccountId.value
          : this.peerAccountId,
      peerDisplayName: data.peerDisplayName.present
          ? data.peerDisplayName.value
          : this.peerDisplayName,
      kind: data.kind.present ? data.kind.value : this.kind,
      direction: data.direction.present ? data.direction.value : this.direction,
      video: data.video.present ? data.video.value : this.video,
      state: data.state.present ? data.state.value : this.state,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      answeredAt: data.answeredAt.present
          ? data.answeredAt.value
          : this.answeredAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CallLogRow(')
          ..write('callId: $callId, ')
          ..write('peerAccountId: $peerAccountId, ')
          ..write('peerDisplayName: $peerDisplayName, ')
          ..write('kind: $kind, ')
          ..write('direction: $direction, ')
          ..write('video: $video, ')
          ..write('state: $state, ')
          ..write('startedAt: $startedAt, ')
          ..write('answeredAt: $answeredAt, ')
          ..write('endedAt: $endedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    callId,
    peerAccountId,
    peerDisplayName,
    kind,
    direction,
    video,
    state,
    startedAt,
    answeredAt,
    endedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CallLogRow &&
          other.callId == this.callId &&
          other.peerAccountId == this.peerAccountId &&
          other.peerDisplayName == this.peerDisplayName &&
          other.kind == this.kind &&
          other.direction == this.direction &&
          other.video == this.video &&
          other.state == this.state &&
          other.startedAt == this.startedAt &&
          other.answeredAt == this.answeredAt &&
          other.endedAt == this.endedAt);
}

class CallLogCompanion extends UpdateCompanion<CallLogRow> {
  final Value<String> callId;
  final Value<String> peerAccountId;
  final Value<String?> peerDisplayName;
  final Value<String> kind;
  final Value<String> direction;
  final Value<bool> video;
  final Value<String> state;
  final Value<DateTime> startedAt;
  final Value<DateTime?> answeredAt;
  final Value<DateTime?> endedAt;
  final Value<int> rowid;
  const CallLogCompanion({
    this.callId = const Value.absent(),
    this.peerAccountId = const Value.absent(),
    this.peerDisplayName = const Value.absent(),
    this.kind = const Value.absent(),
    this.direction = const Value.absent(),
    this.video = const Value.absent(),
    this.state = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.answeredAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CallLogCompanion.insert({
    required String callId,
    required String peerAccountId,
    this.peerDisplayName = const Value.absent(),
    required String kind,
    required String direction,
    this.video = const Value.absent(),
    required String state,
    required DateTime startedAt,
    this.answeredAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : callId = Value(callId),
       peerAccountId = Value(peerAccountId),
       kind = Value(kind),
       direction = Value(direction),
       state = Value(state),
       startedAt = Value(startedAt);
  static Insertable<CallLogRow> custom({
    Expression<String>? callId,
    Expression<String>? peerAccountId,
    Expression<String>? peerDisplayName,
    Expression<String>? kind,
    Expression<String>? direction,
    Expression<bool>? video,
    Expression<String>? state,
    Expression<int>? startedAt,
    Expression<int>? answeredAt,
    Expression<int>? endedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (callId != null) 'call_id': callId,
      if (peerAccountId != null) 'peer_account_id': peerAccountId,
      if (peerDisplayName != null) 'peer_display_name': peerDisplayName,
      if (kind != null) 'kind': kind,
      if (direction != null) 'direction': direction,
      if (video != null) 'video': video,
      if (state != null) 'state': state,
      if (startedAt != null) 'started_at': startedAt,
      if (answeredAt != null) 'answered_at': answeredAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CallLogCompanion copyWith({
    Value<String>? callId,
    Value<String>? peerAccountId,
    Value<String?>? peerDisplayName,
    Value<String>? kind,
    Value<String>? direction,
    Value<bool>? video,
    Value<String>? state,
    Value<DateTime>? startedAt,
    Value<DateTime?>? answeredAt,
    Value<DateTime?>? endedAt,
    Value<int>? rowid,
  }) {
    return CallLogCompanion(
      callId: callId ?? this.callId,
      peerAccountId: peerAccountId ?? this.peerAccountId,
      peerDisplayName: peerDisplayName ?? this.peerDisplayName,
      kind: kind ?? this.kind,
      direction: direction ?? this.direction,
      video: video ?? this.video,
      state: state ?? this.state,
      startedAt: startedAt ?? this.startedAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (callId.present) {
      map['call_id'] = Variable<String>(callId.value);
    }
    if (peerAccountId.present) {
      map['peer_account_id'] = Variable<String>(peerAccountId.value);
    }
    if (peerDisplayName.present) {
      map['peer_display_name'] = Variable<String>(peerDisplayName.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (video.present) {
      map['video'] = Variable<bool>(video.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(
        $CallLogTable.$converterstartedAt.toSql(startedAt.value),
      );
    }
    if (answeredAt.present) {
      map['answered_at'] = Variable<int>(
        $CallLogTable.$converteransweredAtn.toSql(answeredAt.value),
      );
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(
        $CallLogTable.$converterendedAtn.toSql(endedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CallLogCompanion(')
          ..write('callId: $callId, ')
          ..write('peerAccountId: $peerAccountId, ')
          ..write('peerDisplayName: $peerDisplayName, ')
          ..write('kind: $kind, ')
          ..write('direction: $direction, ')
          ..write('video: $video, ')
          ..write('state: $state, ')
          ..write('startedAt: $startedAt, ')
          ..write('answeredAt: $answeredAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SettingsTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: $SettingsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterupdatedAt = const EpochMs();
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const SettingRow({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    {
      map['updated_at'] = Variable<int>(
        $SettingsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SettingRow copyWith({String? key, String? value, DateTime? updatedAt}) =>
      SettingRow(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $SettingsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$HelixDb extends GeneratedDatabase {
  _$HelixDb(QueryExecutor e) : super(e);
  $HelixDbManager get managers => $HelixDbManager(this);
  late final MessagesFts messagesFts = MessagesFts(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final Trigger messagesFtsInsert = Trigger(
    'CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN INSERT INTO messages_fts ("rowid", body) VALUES (new.local_rowid, new.body);END',
    'messages_fts_insert',
  );
  late final Trigger messagesFtsDelete = Trigger(
    'CREATE TRIGGER messages_fts_delete AFTER DELETE ON messages BEGIN INSERT INTO messages_fts (messages_fts, "rowid", body) VALUES (\'delete\', old.local_rowid, old.body);END',
    'messages_fts_delete',
  );
  late final Trigger messagesFtsUpdate = Trigger(
    'CREATE TRIGGER messages_fts_update AFTER UPDATE OF body ON messages BEGIN INSERT INTO messages_fts (messages_fts, "rowid", body) VALUES (\'delete\', old.local_rowid, old.body);INSERT INTO messages_fts ("rowid", body) VALUES (new.local_rowid, new.body);END',
    'messages_fts_update',
  );
  late final $MessageReactionsTable messageReactions = $MessageReactionsTable(
    this,
  );
  late final $MessageReceiptsTable messageReceipts = $MessageReceiptsTable(
    this,
  );
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final Index messagesUnread = Index(
    'messages_unread',
    'CREATE INDEX messages_unread ON messages (conversation_id, status)',
  );
  late final Index messagesMessageId = Index(
    'messages_message_id',
    'CREATE INDEX messages_message_id ON messages (message_id)',
  );
  late final Index messagesExpiresAt = Index(
    'messages_expires_at',
    'CREATE INDEX messages_expires_at ON messages (expires_at)',
  );
  late final $ConversationMembersTable conversationMembers =
      $ConversationMembersTable(this);
  late final Index conversationsList = Index(
    'conversations_list',
    'CREATE INDEX conversations_list ON conversations (archived, last_message_at)',
  );
  late final Index conversationMembersAccount = Index(
    'conversation_members_account',
    'CREATE INDEX conversation_members_account ON conversation_members (account_id)',
  );
  late final $SelfAccountTable selfAccount = $SelfAccountTable(this);
  late final $SelfDevicesTable selfDevices = $SelfDevicesTable(this);
  late final $PeopleTable people = $PeopleTable(this);
  late final $PersonDevicesTable personDevices = $PersonDevicesTable(this);
  late final $IdentityTable identity = $IdentityTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $PrekeysTable prekeys = $PrekeysTable(this);
  late final $SenderKeysTable senderKeys = $SenderKeysTable(this);
  late final $InboxCursorTable inboxCursor = $InboxCursorTable(this);
  late final $ProcessedEnvelopesTable processedEnvelopes =
      $ProcessedEnvelopesTable(this);
  late final $OutboxOpsTable outboxOps = $OutboxOpsTable(this);
  late final $DeferredActionsTable deferredActions = $DeferredActionsTable(
    this,
  );
  late final $TransferJobsTable transferJobs = $TransferJobsTable(this);
  late final $TransferChunksTable transferChunks = $TransferChunksTable(this);
  late final $GroupsTable groups = $GroupsTable(this);
  late final $GroupMembersTable groupMembers = $GroupMembersTable(this);
  late final $GroupBansTable groupBans = $GroupBansTable(this);
  late final $CallLogTable callLog = $CallLogTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index peoplePhoneHash = Index(
    'people_phone_hash',
    'CREATE INDEX people_phone_hash ON people (phone_hash)',
  );
  late final Index processedEnvelopesAt = Index(
    'processed_envelopes_at',
    'CREATE INDEX processed_envelopes_at ON processed_envelopes (processed_at)',
  );
  late final Index outboxOpsDue = Index(
    'outbox_ops_due',
    'CREATE INDEX outbox_ops_due ON outbox_ops (state, next_attempt_at)',
  );
  late final Index deferredActionsTarget = Index(
    'deferred_actions_target',
    'CREATE INDEX deferred_actions_target ON deferred_actions (target_message_id, target_author)',
  );
  late final Index deferredActionsExpiry = Index(
    'deferred_actions_expiry',
    'CREATE INDEX deferred_actions_expiry ON deferred_actions (expires_at)',
  );
  late final Index transferJobsState = Index(
    'transfer_jobs_state',
    'CREATE INDEX transfer_jobs_state ON transfer_jobs (state, next_attempt_at)',
  );
  late final Index transferChunksTransfer = Index(
    'transfer_chunks_transfer',
    'CREATE INDEX transfer_chunks_transfer ON transfer_chunks (transfer_id, sequence)',
  );
  late final Index groupsList = Index(
    'groups_list',
    'CREATE INDEX groups_list ON "groups" (archived)',
  );
  late final Index groupMembersAccount = Index(
    'group_members_account',
    'CREATE INDEX group_members_account ON group_members (account_id)',
  );
  late final Index callLogAt = Index(
    'call_log_at',
    'CREATE INDEX call_log_at ON call_log (started_at)',
  );
  late final AccountDao accountDao = AccountDao(this as HelixDb);
  late final PeopleDao peopleDao = PeopleDao(this as HelixDb);
  late final ConversationsDao conversationsDao = ConversationsDao(
    this as HelixDb,
  );
  late final MessagesDao messagesDao = MessagesDao(this as HelixDb);
  late final CryptoDao cryptoDao = CryptoDao(this as HelixDb);
  late final InboxDao inboxDao = InboxDao(this as HelixDb);
  late final OutboxDao outboxDao = OutboxDao(this as HelixDb);
  late final SettingsDao settingsDao = SettingsDao(this as HelixDb);
  late final GroupsDao groupsDao = GroupsDao(this as HelixDb);
  late final TransfersDao transfersDao = TransfersDao(this as HelixDb);
  late final CallsDao callsDao = CallsDao(this as HelixDb);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    messagesFts,
    conversations,
    messages,
    messagesFtsInsert,
    messagesFtsDelete,
    messagesFtsUpdate,
    messageReactions,
    messageReceipts,
    attachments,
    messagesUnread,
    messagesMessageId,
    messagesExpiresAt,
    conversationMembers,
    conversationsList,
    conversationMembersAccount,
    selfAccount,
    selfDevices,
    people,
    personDevices,
    identity,
    sessions,
    prekeys,
    senderKeys,
    inboxCursor,
    processedEnvelopes,
    outboxOps,
    deferredActions,
    transferJobs,
    transferChunks,
    groups,
    groupMembers,
    groupBans,
    callLog,
    settings,
    peoplePhoneHash,
    processedEnvelopesAt,
    outboxOpsDue,
    deferredActionsTarget,
    deferredActionsExpiry,
    transferJobsState,
    transferChunksTransfer,
    groupsList,
    groupMembersAccount,
    callLogAt,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('messages_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [TableUpdate('messages_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('message_reactions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('message_receipts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('attachments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversation_members', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('outbox_ops', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('outbox_ops', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'attachments',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('transfer_jobs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('group_members', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('group_bans', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $MessagesFtsCreateCompanionBuilder =
    MessagesFtsCompanion Function({required String body, Value<int> rowid});
typedef $MessagesFtsUpdateCompanionBuilder =
    MessagesFtsCompanion Function({Value<String> body, Value<int> rowid});

class $MessagesFtsFilterComposer extends Composer<_$HelixDb, MessagesFts> {
  $MessagesFtsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $MessagesFtsOrderingComposer extends Composer<_$HelixDb, MessagesFts> {
  $MessagesFtsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $MessagesFtsAnnotationComposer extends Composer<_$HelixDb, MessagesFts> {
  $MessagesFtsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $MessagesFtsTableManager
    extends
        RootTableManager<
          _$HelixDb,
          MessagesFts,
          MessagesFt,
          $MessagesFtsFilterComposer,
          $MessagesFtsOrderingComposer,
          $MessagesFtsAnnotationComposer,
          $MessagesFtsCreateCompanionBuilder,
          $MessagesFtsUpdateCompanionBuilder,
          (MessagesFt, BaseReferences<_$HelixDb, MessagesFts, MessagesFt>),
          MessagesFt,
          PrefetchHooks Function()
        > {
  $MessagesFtsTableManager(_$HelixDb db, MessagesFts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MessagesFtsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MessagesFtsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MessagesFtsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesFtsCompanion(body: body, rowid: rowid),
          createCompanionCallback:
              ({
                required String body,
                Value<int> rowid = const Value.absent(),
              }) => MessagesFtsCompanion.insert(body: body, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $MessagesFtsProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      MessagesFts,
      MessagesFt,
      $MessagesFtsFilterComposer,
      $MessagesFtsOrderingComposer,
      $MessagesFtsAnnotationComposer,
      $MessagesFtsCreateCompanionBuilder,
      $MessagesFtsUpdateCompanionBuilder,
      (MessagesFt, BaseReferences<_$HelixDb, MessagesFts, MessagesFt>),
      MessagesFt,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String id,
      required ConversationKind kind,
      Value<String?> title,
      Value<Uint8List?> avatar,
      Value<DateTime?> pinnedAt,
      Value<DateTime?> mutedUntil,
      Value<bool> archived,
      Value<int?> lastMessageRowid,
      Value<String?> lastMessageSortKey,
      Value<DateTime?> lastMessageAt,
      Value<String?> lastMessagePreview,
      Value<int> unreadCount,
      Value<int> mentionCount,
      Value<String?> lastReadSortKey,
      Value<String?> draft,
      Value<int?> disappearingSeconds,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> id,
      Value<ConversationKind> kind,
      Value<String?> title,
      Value<Uint8List?> avatar,
      Value<DateTime?> pinnedAt,
      Value<DateTime?> mutedUntil,
      Value<bool> archived,
      Value<int?> lastMessageRowid,
      Value<String?> lastMessageSortKey,
      Value<DateTime?> lastMessageAt,
      Value<String?> lastMessagePreview,
      Value<int> unreadCount,
      Value<int> mentionCount,
      Value<String?> lastReadSortKey,
      Value<String?> draft,
      Value<int?> disappearingSeconds,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ConversationsTableReferences
    extends BaseReferences<_$HelixDb, $ConversationsTable, ConversationRow> {
  $$ConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$MessagesTable, List<MessageRow>>
  _messagesRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'conversations__id__messages__conversation_id',
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ConversationMembersTable,
    List<ConversationMemberRow>
  >
  _conversationMembersRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.conversationMembers,
    aliasName: 'conversations__id__conversation_members__conversation_id',
  );

  $$ConversationMembersTableProcessedTableManager get conversationMembersRefs {
    final manager = $$ConversationMembersTableTableManager(
      $_db,
      $_db.conversationMembers,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _conversationMembersRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OutboxOpsTable, List<OutboxOpRow>>
  _outboxOpsRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.outboxOps,
    aliasName: 'conversations__id__outbox_ops__conversation_id',
  );

  $$OutboxOpsTableProcessedTableManager get outboxOpsRefs {
    final manager = $$OutboxOpsTableTableManager(
      $_db,
      $_db.outboxOps,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_outboxOpsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConversationsTableFilterComposer
    extends Composer<_$HelixDb, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ConversationKind, ConversationKind, String>
  get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get pinnedAt =>
      $composableBuilder(
        column: $table.pinnedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get mutedUntil =>
      $composableBuilder(
        column: $table.mutedUntil,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastMessageRowid => $composableBuilder(
    column: $table.lastMessageRowid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageSortKey => $composableBuilder(
    column: $table.lastMessageSortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get lastMessageAt =>
      $composableBuilder(
        column: $table.lastMessageAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mentionCount => $composableBuilder(
    column: $table.mentionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastReadSortKey => $composableBuilder(
    column: $table.lastReadSortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get draft => $composableBuilder(
    column: $table.draft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get disappearingSeconds => $composableBuilder(
    column: $table.disappearingSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> conversationMembersRefs(
    Expression<bool> Function($$ConversationMembersTableFilterComposer f) f,
  ) {
    final $$ConversationMembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversationMembers,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationMembersTableFilterComposer(
            $db: $db,
            $table: $db.conversationMembers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> outboxOpsRefs(
    Expression<bool> Function($$OutboxOpsTableFilterComposer f) f,
  ) {
    final $$OutboxOpsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outboxOps,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxOpsTableFilterComposer(
            $db: $db,
            $table: $db.outboxOps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$HelixDb, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mutedUntil => $composableBuilder(
    column: $table.mutedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageRowid => $composableBuilder(
    column: $table.lastMessageRowid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageSortKey => $composableBuilder(
    column: $table.lastMessageSortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mentionCount => $composableBuilder(
    column: $table.mentionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastReadSortKey => $composableBuilder(
    column: $table.lastReadSortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get draft => $composableBuilder(
    column: $table.draft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get disappearingSeconds => $composableBuilder(
    column: $table.disappearingSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$HelixDb, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ConversationKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<Uint8List> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get mutedUntil =>
      $composableBuilder(
        column: $table.mutedUntil,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<int> get lastMessageRowid => $composableBuilder(
    column: $table.lastMessageRowid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageSortKey => $composableBuilder(
    column: $table.lastMessageSortKey,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastMessageAt =>
      $composableBuilder(
        column: $table.lastMessageAt,
        builder: (column) => column,
      );

  GeneratedColumn<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mentionCount => $composableBuilder(
    column: $table.mentionCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastReadSortKey => $composableBuilder(
    column: $table.lastReadSortKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get draft =>
      $composableBuilder(column: $table.draft, builder: (column) => column);

  GeneratedColumn<int> get disappearingSeconds => $composableBuilder(
    column: $table.disappearingSeconds,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> conversationMembersRefs<T extends Object>(
    Expression<T> Function($$ConversationMembersTableAnnotationComposer a) f,
  ) {
    final $$ConversationMembersTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.conversationMembers,
          getReferencedColumn: (t) => t.conversationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ConversationMembersTableAnnotationComposer(
                $db: $db,
                $table: $db.conversationMembers,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> outboxOpsRefs<T extends Object>(
    Expression<T> Function($$OutboxOpsTableAnnotationComposer a) f,
  ) {
    final $$OutboxOpsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outboxOps,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxOpsTableAnnotationComposer(
            $db: $db,
            $table: $db.outboxOps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $ConversationsTable,
          ConversationRow,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (ConversationRow, $$ConversationsTableReferences),
          ConversationRow,
          PrefetchHooks Function({
            bool messagesRefs,
            bool conversationMembersRefs,
            bool outboxOpsRefs,
          })
        > {
  $$ConversationsTableTableManager(_$HelixDb db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<ConversationKind> kind = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<Uint8List?> avatar = const Value.absent(),
                Value<DateTime?> pinnedAt = const Value.absent(),
                Value<DateTime?> mutedUntil = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<int?> lastMessageRowid = const Value.absent(),
                Value<String?> lastMessageSortKey = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> mentionCount = const Value.absent(),
                Value<String?> lastReadSortKey = const Value.absent(),
                Value<String?> draft = const Value.absent(),
                Value<int?> disappearingSeconds = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                kind: kind,
                title: title,
                avatar: avatar,
                pinnedAt: pinnedAt,
                mutedUntil: mutedUntil,
                archived: archived,
                lastMessageRowid: lastMessageRowid,
                lastMessageSortKey: lastMessageSortKey,
                lastMessageAt: lastMessageAt,
                lastMessagePreview: lastMessagePreview,
                unreadCount: unreadCount,
                mentionCount: mentionCount,
                lastReadSortKey: lastReadSortKey,
                draft: draft,
                disappearingSeconds: disappearingSeconds,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required ConversationKind kind,
                Value<String?> title = const Value.absent(),
                Value<Uint8List?> avatar = const Value.absent(),
                Value<DateTime?> pinnedAt = const Value.absent(),
                Value<DateTime?> mutedUntil = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<int?> lastMessageRowid = const Value.absent(),
                Value<String?> lastMessageSortKey = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> mentionCount = const Value.absent(),
                Value<String?> lastReadSortKey = const Value.absent(),
                Value<String?> draft = const Value.absent(),
                Value<int?> disappearingSeconds = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                kind: kind,
                title: title,
                avatar: avatar,
                pinnedAt: pinnedAt,
                mutedUntil: mutedUntil,
                archived: archived,
                lastMessageRowid: lastMessageRowid,
                lastMessageSortKey: lastMessageSortKey,
                lastMessageAt: lastMessageAt,
                lastMessagePreview: lastMessagePreview,
                unreadCount: unreadCount,
                mentionCount: mentionCount,
                lastReadSortKey: lastReadSortKey,
                draft: draft,
                disappearingSeconds: disappearingSeconds,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                messagesRefs = false,
                conversationMembersRefs = false,
                outboxOpsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (messagesRefs) db.messages,
                    if (conversationMembersRefs) db.conversationMembers,
                    if (outboxOpsRefs) db.outboxOps,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (messagesRefs)
                        await $_getPrefetchedData<
                          ConversationRow,
                          $ConversationsTable,
                          MessageRow
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._messagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).messagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (conversationMembersRefs)
                        await $_getPrefetchedData<
                          ConversationRow,
                          $ConversationsTable,
                          ConversationMemberRow
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._conversationMembersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).conversationMembersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (outboxOpsRefs)
                        await $_getPrefetchedData<
                          ConversationRow,
                          $ConversationsTable,
                          OutboxOpRow
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._outboxOpsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).outboxOpsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $ConversationsTable,
      ConversationRow,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (ConversationRow, $$ConversationsTableReferences),
      ConversationRow,
      PrefetchHooks Function({
        bool messagesRefs,
        bool conversationMembersRefs,
        bool outboxOpsRefs,
      })
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> localRowid,
      required String messageId,
      required String conversationId,
      required String sender,
      Value<String?> senderDevice,
      required bool outgoing,
      required String sortKey,
      required DateTime sentAt,
      required DateTime receivedAt,
      required String kind,
      Value<String?> body,
      Value<String?> payload,
      Value<String?> replyToId,
      Value<String?> replyToAuthor,
      Value<bool> forwarded,
      Value<bool> mentionsMe,
      required MessageStatus status,
      Value<DateTime?> editedAt,
      Value<DateTime?> deletedAt,
      Value<int?> expireSeconds,
      Value<DateTime?> expiresAt,
      Value<ViewOnceState?> viewOnceState,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> localRowid,
      Value<String> messageId,
      Value<String> conversationId,
      Value<String> sender,
      Value<String?> senderDevice,
      Value<bool> outgoing,
      Value<String> sortKey,
      Value<DateTime> sentAt,
      Value<DateTime> receivedAt,
      Value<String> kind,
      Value<String?> body,
      Value<String?> payload,
      Value<String?> replyToId,
      Value<String?> replyToAuthor,
      Value<bool> forwarded,
      Value<bool> mentionsMe,
      Value<MessageStatus> status,
      Value<DateTime?> editedAt,
      Value<DateTime?> deletedAt,
      Value<int?> expireSeconds,
      Value<DateTime?> expiresAt,
      Value<ViewOnceState?> viewOnceState,
    });

final class $$MessagesTableReferences
    extends BaseReferences<_$HelixDb, $MessagesTable, MessageRow> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConversationsTable _conversationIdTable(_$HelixDb db) => db
      .conversations
      .createAlias('messages__conversation_id__conversations__id');

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MessageReactionsTable, List<ReactionRow>>
  _messageReactionsRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.messageReactions,
    aliasName: 'messages__local_rowid__message_reactions__message_rowid',
  );

  $$MessageReactionsTableProcessedTableManager get messageReactionsRefs {
    final manager =
        $$MessageReactionsTableTableManager($_db, $_db.messageReactions).filter(
          (f) => f.messageRowid.localRowid.sqlEquals(
            $_itemColumn<int>('local_rowid')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _messageReactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MessageReceiptsTable, List<ReceiptRow>>
  _messageReceiptsRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.messageReceipts,
    aliasName: 'messages__local_rowid__message_receipts__message_rowid',
  );

  $$MessageReceiptsTableProcessedTableManager get messageReceiptsRefs {
    final manager =
        $$MessageReceiptsTableTableManager($_db, $_db.messageReceipts).filter(
          (f) => f.messageRowid.localRowid.sqlEquals(
            $_itemColumn<int>('local_rowid')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _messageReceiptsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AttachmentsTable, List<AttachmentRow>>
  _attachmentsRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.attachments,
    aliasName: 'messages__local_rowid__attachments__message_rowid',
  );

  $$AttachmentsTableProcessedTableManager get attachmentsRefs {
    final manager = $$AttachmentsTableTableManager($_db, $_db.attachments)
        .filter(
          (f) => f.messageRowid.localRowid.sqlEquals(
            $_itemColumn<int>('local_rowid')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_attachmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OutboxOpsTable, List<OutboxOpRow>>
  _outboxOpsRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.outboxOps,
    aliasName: 'messages__local_rowid__outbox_ops__message_rowid',
  );

  $$OutboxOpsTableProcessedTableManager get outboxOpsRefs {
    final manager = $$OutboxOpsTableTableManager($_db, $_db.outboxOps).filter(
      (f) => f.messageRowid.localRowid.sqlEquals(
        $_itemColumn<int>('local_rowid')!,
      ),
    );

    final cache = $_typedResult.readTableOrNull(_outboxOpsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$HelixDb, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localRowid => $composableBuilder(
    column: $table.localRowid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get outgoing => $composableBuilder(
    column: $table.outgoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get sentAt =>
      $composableBuilder(
        column: $table.sentAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get receivedAt =>
      $composableBuilder(
        column: $table.receivedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToAuthor => $composableBuilder(
    column: $table.replyToAuthor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get forwarded => $composableBuilder(
    column: $table.forwarded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get mentionsMe => $composableBuilder(
    column: $table.mentionsMe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageStatus, MessageStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get editedAt =>
      $composableBuilder(
        column: $table.editedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get expireSeconds => $composableBuilder(
    column: $table.expireSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get expiresAt =>
      $composableBuilder(
        column: $table.expiresAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<ViewOnceState?, ViewOnceState, String>
  get viewOnceState => $composableBuilder(
    column: $table.viewOnceState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> messageReactionsRefs(
    Expression<bool> Function($$MessageReactionsTableFilterComposer f) f,
  ) {
    final $$MessageReactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localRowid,
      referencedTable: $db.messageReactions,
      getReferencedColumn: (t) => t.messageRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageReactionsTableFilterComposer(
            $db: $db,
            $table: $db.messageReactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> messageReceiptsRefs(
    Expression<bool> Function($$MessageReceiptsTableFilterComposer f) f,
  ) {
    final $$MessageReceiptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localRowid,
      referencedTable: $db.messageReceipts,
      getReferencedColumn: (t) => t.messageRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageReceiptsTableFilterComposer(
            $db: $db,
            $table: $db.messageReceipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> attachmentsRefs(
    Expression<bool> Function($$AttachmentsTableFilterComposer f) f,
  ) {
    final $$AttachmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localRowid,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.messageRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentsTableFilterComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> outboxOpsRefs(
    Expression<bool> Function($$OutboxOpsTableFilterComposer f) f,
  ) {
    final $$OutboxOpsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localRowid,
      referencedTable: $db.outboxOps,
      getReferencedColumn: (t) => t.messageRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxOpsTableFilterComposer(
            $db: $db,
            $table: $db.outboxOps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$HelixDb, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localRowid => $composableBuilder(
    column: $table.localRowid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get outgoing => $composableBuilder(
    column: $table.outgoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToId => $composableBuilder(
    column: $table.replyToId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToAuthor => $composableBuilder(
    column: $table.replyToAuthor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get forwarded => $composableBuilder(
    column: $table.forwarded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get mentionsMe => $composableBuilder(
    column: $table.mentionsMe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get editedAt => $composableBuilder(
    column: $table.editedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expireSeconds => $composableBuilder(
    column: $table.expireSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get viewOnceState => $composableBuilder(
    column: $table.viewOnceState,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$HelixDb, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localRowid => $composableBuilder(
    column: $table.localRowid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => column);

  GeneratedColumn<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get outgoing =>
      $composableBuilder(column: $table.outgoing, builder: (column) => column);

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get receivedAt =>
      $composableBuilder(
        column: $table.receivedAt,
        builder: (column) => column,
      );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get replyToId =>
      $composableBuilder(column: $table.replyToId, builder: (column) => column);

  GeneratedColumn<String> get replyToAuthor => $composableBuilder(
    column: $table.replyToAuthor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get forwarded =>
      $composableBuilder(column: $table.forwarded, builder: (column) => column);

  GeneratedColumn<bool> get mentionsMe => $composableBuilder(
    column: $table.mentionsMe,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<MessageStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get expireSeconds => $composableBuilder(
    column: $table.expireSeconds,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ViewOnceState?, String> get viewOnceState =>
      $composableBuilder(
        column: $table.viewOnceState,
        builder: (column) => column,
      );

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> messageReactionsRefs<T extends Object>(
    Expression<T> Function($$MessageReactionsTableAnnotationComposer a) f,
  ) {
    final $$MessageReactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localRowid,
      referencedTable: $db.messageReactions,
      getReferencedColumn: (t) => t.messageRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageReactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.messageReactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> messageReceiptsRefs<T extends Object>(
    Expression<T> Function($$MessageReceiptsTableAnnotationComposer a) f,
  ) {
    final $$MessageReceiptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localRowid,
      referencedTable: $db.messageReceipts,
      getReferencedColumn: (t) => t.messageRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageReceiptsTableAnnotationComposer(
            $db: $db,
            $table: $db.messageReceipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> attachmentsRefs<T extends Object>(
    Expression<T> Function($$AttachmentsTableAnnotationComposer a) f,
  ) {
    final $$AttachmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localRowid,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.messageRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> outboxOpsRefs<T extends Object>(
    Expression<T> Function($$OutboxOpsTableAnnotationComposer a) f,
  ) {
    final $$OutboxOpsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localRowid,
      referencedTable: $db.outboxOps,
      getReferencedColumn: (t) => t.messageRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxOpsTableAnnotationComposer(
            $db: $db,
            $table: $db.outboxOps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $MessagesTable,
          MessageRow,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (MessageRow, $$MessagesTableReferences),
          MessageRow,
          PrefetchHooks Function({
            bool conversationId,
            bool messageReactionsRefs,
            bool messageReceiptsRefs,
            bool attachmentsRefs,
            bool outboxOpsRefs,
          })
        > {
  $$MessagesTableTableManager(_$HelixDb db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> localRowid = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> sender = const Value.absent(),
                Value<String?> senderDevice = const Value.absent(),
                Value<bool> outgoing = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<DateTime> sentAt = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> replyToAuthor = const Value.absent(),
                Value<bool> forwarded = const Value.absent(),
                Value<bool> mentionsMe = const Value.absent(),
                Value<MessageStatus> status = const Value.absent(),
                Value<DateTime?> editedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int?> expireSeconds = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<ViewOnceState?> viewOnceState = const Value.absent(),
              }) => MessagesCompanion(
                localRowid: localRowid,
                messageId: messageId,
                conversationId: conversationId,
                sender: sender,
                senderDevice: senderDevice,
                outgoing: outgoing,
                sortKey: sortKey,
                sentAt: sentAt,
                receivedAt: receivedAt,
                kind: kind,
                body: body,
                payload: payload,
                replyToId: replyToId,
                replyToAuthor: replyToAuthor,
                forwarded: forwarded,
                mentionsMe: mentionsMe,
                status: status,
                editedAt: editedAt,
                deletedAt: deletedAt,
                expireSeconds: expireSeconds,
                expiresAt: expiresAt,
                viewOnceState: viewOnceState,
              ),
          createCompanionCallback:
              ({
                Value<int> localRowid = const Value.absent(),
                required String messageId,
                required String conversationId,
                required String sender,
                Value<String?> senderDevice = const Value.absent(),
                required bool outgoing,
                required String sortKey,
                required DateTime sentAt,
                required DateTime receivedAt,
                required String kind,
                Value<String?> body = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<String?> replyToId = const Value.absent(),
                Value<String?> replyToAuthor = const Value.absent(),
                Value<bool> forwarded = const Value.absent(),
                Value<bool> mentionsMe = const Value.absent(),
                required MessageStatus status,
                Value<DateTime?> editedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int?> expireSeconds = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<ViewOnceState?> viewOnceState = const Value.absent(),
              }) => MessagesCompanion.insert(
                localRowid: localRowid,
                messageId: messageId,
                conversationId: conversationId,
                sender: sender,
                senderDevice: senderDevice,
                outgoing: outgoing,
                sortKey: sortKey,
                sentAt: sentAt,
                receivedAt: receivedAt,
                kind: kind,
                body: body,
                payload: payload,
                replyToId: replyToId,
                replyToAuthor: replyToAuthor,
                forwarded: forwarded,
                mentionsMe: mentionsMe,
                status: status,
                editedAt: editedAt,
                deletedAt: deletedAt,
                expireSeconds: expireSeconds,
                expiresAt: expiresAt,
                viewOnceState: viewOnceState,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                conversationId = false,
                messageReactionsRefs = false,
                messageReceiptsRefs = false,
                attachmentsRefs = false,
                outboxOpsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (messageReactionsRefs) db.messageReactions,
                    if (messageReceiptsRefs) db.messageReceipts,
                    if (attachmentsRefs) db.attachments,
                    if (outboxOpsRefs) db.outboxOps,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (conversationId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.conversationId,
                                    referencedTable: $$MessagesTableReferences
                                        ._conversationIdTable(db),
                                    referencedColumn: $$MessagesTableReferences
                                        ._conversationIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (messageReactionsRefs)
                        await $_getPrefetchedData<
                          MessageRow,
                          $MessagesTable,
                          ReactionRow
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._messageReactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).messageReactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageRowid == item.localRowid,
                              ),
                          typedResults: items,
                        ),
                      if (messageReceiptsRefs)
                        await $_getPrefetchedData<
                          MessageRow,
                          $MessagesTable,
                          ReceiptRow
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._messageReceiptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).messageReceiptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageRowid == item.localRowid,
                              ),
                          typedResults: items,
                        ),
                      if (attachmentsRefs)
                        await $_getPrefetchedData<
                          MessageRow,
                          $MessagesTable,
                          AttachmentRow
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._attachmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).attachmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageRowid == item.localRowid,
                              ),
                          typedResults: items,
                        ),
                      if (outboxOpsRefs)
                        await $_getPrefetchedData<
                          MessageRow,
                          $MessagesTable,
                          OutboxOpRow
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._outboxOpsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).outboxOpsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageRowid == item.localRowid,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $MessagesTable,
      MessageRow,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (MessageRow, $$MessagesTableReferences),
      MessageRow,
      PrefetchHooks Function({
        bool conversationId,
        bool messageReactionsRefs,
        bool messageReceiptsRefs,
        bool attachmentsRefs,
        bool outboxOpsRefs,
      })
    >;
typedef $$MessageReactionsTableCreateCompanionBuilder =
    MessageReactionsCompanion Function({
      required int messageRowid,
      required String reactor,
      required String emoji,
      required DateTime reactedAt,
      Value<int> rowid,
    });
typedef $$MessageReactionsTableUpdateCompanionBuilder =
    MessageReactionsCompanion Function({
      Value<int> messageRowid,
      Value<String> reactor,
      Value<String> emoji,
      Value<DateTime> reactedAt,
      Value<int> rowid,
    });

final class $$MessageReactionsTableReferences
    extends BaseReferences<_$HelixDb, $MessageReactionsTable, ReactionRow> {
  $$MessageReactionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MessagesTable _messageRowidTable(_$HelixDb db) => db.messages
      .createAlias('message_reactions__message_rowid__messages__local_rowid');

  $$MessagesTableProcessedTableManager get messageRowid {
    final $_column = $_itemColumn<int>('message_rowid')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.localRowid.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageRowidTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessageReactionsTableFilterComposer
    extends Composer<_$HelixDb, $MessageReactionsTable> {
  $$MessageReactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get reactor => $composableBuilder(
    column: $table.reactor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get reactedAt =>
      $composableBuilder(
        column: $table.reactedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$MessagesTableFilterComposer get messageRowid {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReactionsTableOrderingComposer
    extends Composer<_$HelixDb, $MessageReactionsTable> {
  $$MessageReactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get reactor => $composableBuilder(
    column: $table.reactor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reactedAt => $composableBuilder(
    column: $table.reactedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MessagesTableOrderingComposer get messageRowid {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReactionsTableAnnotationComposer
    extends Composer<_$HelixDb, $MessageReactionsTable> {
  $$MessageReactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get reactor =>
      $composableBuilder(column: $table.reactor, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get reactedAt =>
      $composableBuilder(column: $table.reactedAt, builder: (column) => column);

  $$MessagesTableAnnotationComposer get messageRowid {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReactionsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $MessageReactionsTable,
          ReactionRow,
          $$MessageReactionsTableFilterComposer,
          $$MessageReactionsTableOrderingComposer,
          $$MessageReactionsTableAnnotationComposer,
          $$MessageReactionsTableCreateCompanionBuilder,
          $$MessageReactionsTableUpdateCompanionBuilder,
          (ReactionRow, $$MessageReactionsTableReferences),
          ReactionRow,
          PrefetchHooks Function({bool messageRowid})
        > {
  $$MessageReactionsTableTableManager(
    _$HelixDb db,
    $MessageReactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageReactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageReactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageReactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> messageRowid = const Value.absent(),
                Value<String> reactor = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<DateTime> reactedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageReactionsCompanion(
                messageRowid: messageRowid,
                reactor: reactor,
                emoji: emoji,
                reactedAt: reactedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int messageRowid,
                required String reactor,
                required String emoji,
                required DateTime reactedAt,
                Value<int> rowid = const Value.absent(),
              }) => MessageReactionsCompanion.insert(
                messageRowid: messageRowid,
                reactor: reactor,
                emoji: emoji,
                reactedAt: reactedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessageReactionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageRowid = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (messageRowid) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.messageRowid,
                                referencedTable:
                                    $$MessageReactionsTableReferences
                                        ._messageRowidTable(db),
                                referencedColumn:
                                    $$MessageReactionsTableReferences
                                        ._messageRowidTable(db)
                                        .localRowid,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessageReactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $MessageReactionsTable,
      ReactionRow,
      $$MessageReactionsTableFilterComposer,
      $$MessageReactionsTableOrderingComposer,
      $$MessageReactionsTableAnnotationComposer,
      $$MessageReactionsTableCreateCompanionBuilder,
      $$MessageReactionsTableUpdateCompanionBuilder,
      (ReactionRow, $$MessageReactionsTableReferences),
      ReactionRow,
      PrefetchHooks Function({bool messageRowid})
    >;
typedef $$MessageReceiptsTableCreateCompanionBuilder =
    MessageReceiptsCompanion Function({
      required int messageRowid,
      required String accountId,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<DateTime?> viewedAt,
      Value<int> rowid,
    });
typedef $$MessageReceiptsTableUpdateCompanionBuilder =
    MessageReceiptsCompanion Function({
      Value<int> messageRowid,
      Value<String> accountId,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<DateTime?> viewedAt,
      Value<int> rowid,
    });

final class $$MessageReceiptsTableReferences
    extends BaseReferences<_$HelixDb, $MessageReceiptsTable, ReceiptRow> {
  $$MessageReceiptsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MessagesTable _messageRowidTable(_$HelixDb db) => db.messages
      .createAlias('message_receipts__message_rowid__messages__local_rowid');

  $$MessagesTableProcessedTableManager get messageRowid {
    final $_column = $_itemColumn<int>('message_rowid')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.localRowid.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageRowidTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessageReceiptsTableFilterComposer
    extends Composer<_$HelixDb, $MessageReceiptsTable> {
  $$MessageReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get deliveredAt =>
      $composableBuilder(
        column: $table.deliveredAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get readAt =>
      $composableBuilder(
        column: $table.readAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get viewedAt =>
      $composableBuilder(
        column: $table.viewedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$MessagesTableFilterComposer get messageRowid {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReceiptsTableOrderingComposer
    extends Composer<_$HelixDb, $MessageReceiptsTable> {
  $$MessageReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get viewedAt => $composableBuilder(
    column: $table.viewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MessagesTableOrderingComposer get messageRowid {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReceiptsTableAnnotationComposer
    extends Composer<_$HelixDb, $MessageReceiptsTable> {
  $$MessageReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get deliveredAt =>
      $composableBuilder(
        column: $table.deliveredAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get viewedAt =>
      $composableBuilder(column: $table.viewedAt, builder: (column) => column);

  $$MessagesTableAnnotationComposer get messageRowid {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageReceiptsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $MessageReceiptsTable,
          ReceiptRow,
          $$MessageReceiptsTableFilterComposer,
          $$MessageReceiptsTableOrderingComposer,
          $$MessageReceiptsTableAnnotationComposer,
          $$MessageReceiptsTableCreateCompanionBuilder,
          $$MessageReceiptsTableUpdateCompanionBuilder,
          (ReceiptRow, $$MessageReceiptsTableReferences),
          ReceiptRow,
          PrefetchHooks Function({bool messageRowid})
        > {
  $$MessageReceiptsTableTableManager(_$HelixDb db, $MessageReceiptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> messageRowid = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<DateTime?> viewedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageReceiptsCompanion(
                messageRowid: messageRowid,
                accountId: accountId,
                deliveredAt: deliveredAt,
                readAt: readAt,
                viewedAt: viewedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int messageRowid,
                required String accountId,
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<DateTime?> viewedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageReceiptsCompanion.insert(
                messageRowid: messageRowid,
                accountId: accountId,
                deliveredAt: deliveredAt,
                readAt: readAt,
                viewedAt: viewedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessageReceiptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageRowid = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (messageRowid) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.messageRowid,
                                referencedTable:
                                    $$MessageReceiptsTableReferences
                                        ._messageRowidTable(db),
                                referencedColumn:
                                    $$MessageReceiptsTableReferences
                                        ._messageRowidTable(db)
                                        .localRowid,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessageReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $MessageReceiptsTable,
      ReceiptRow,
      $$MessageReceiptsTableFilterComposer,
      $$MessageReceiptsTableOrderingComposer,
      $$MessageReceiptsTableAnnotationComposer,
      $$MessageReceiptsTableCreateCompanionBuilder,
      $$MessageReceiptsTableUpdateCompanionBuilder,
      (ReceiptRow, $$MessageReceiptsTableReferences),
      ReceiptRow,
      PrefetchHooks Function({bool messageRowid})
    >;
typedef $$AttachmentsTableCreateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<int> id,
      required int messageRowid,
      required int position,
      required String kind,
      required String mediaId,
      required Uint8List mediaKey,
      required Uint8List digest,
      required String mime,
      required int size,
      Value<String?> name,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<Uint8List?> waveform,
      Value<String?> blurhash,
      Value<String?> caption,
      Value<String?> thumbnail,
      Value<String?> thumbnailPath,
      Value<String?> localPath,
      required AttachmentTransfer transfer,
    });
typedef $$AttachmentsTableUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<int> id,
      Value<int> messageRowid,
      Value<int> position,
      Value<String> kind,
      Value<String> mediaId,
      Value<Uint8List> mediaKey,
      Value<Uint8List> digest,
      Value<String> mime,
      Value<int> size,
      Value<String?> name,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<Uint8List?> waveform,
      Value<String?> blurhash,
      Value<String?> caption,
      Value<String?> thumbnail,
      Value<String?> thumbnailPath,
      Value<String?> localPath,
      Value<AttachmentTransfer> transfer,
    });

final class $$AttachmentsTableReferences
    extends BaseReferences<_$HelixDb, $AttachmentsTable, AttachmentRow> {
  $$AttachmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MessagesTable _messageRowidTable(_$HelixDb db) => db.messages
      .createAlias('attachments__message_rowid__messages__local_rowid');

  $$MessagesTableProcessedTableManager get messageRowid {
    final $_column = $_itemColumn<int>('message_rowid')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.localRowid.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageRowidTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TransferJobsTable, List<TransferRow>>
  _transferJobsRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.transferJobs,
    aliasName: 'attachments__id__transfer_jobs__attachment_rowid',
  );

  $$TransferJobsTableProcessedTableManager get transferJobsRefs {
    final manager = $$TransferJobsTableTableManager(
      $_db,
      $_db.transferJobs,
    ).filter((f) => f.attachmentRowid.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_transferJobsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AttachmentsTableFilterComposer
    extends Composer<_$HelixDb, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get waveform => $composableBuilder(
    column: $table.waveform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blurhash => $composableBuilder(
    column: $table.blurhash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnail => $composableBuilder(
    column: $table.thumbnail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AttachmentTransfer, AttachmentTransfer, String>
  get transfer => $composableBuilder(
    column: $table.transfer,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  $$MessagesTableFilterComposer get messageRowid {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> transferJobsRefs(
    Expression<bool> Function($$TransferJobsTableFilterComposer f) f,
  ) {
    final $$TransferJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transferJobs,
      getReferencedColumn: (t) => t.attachmentRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransferJobsTableFilterComposer(
            $db: $db,
            $table: $db.transferJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$HelixDb, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get waveform => $composableBuilder(
    column: $table.waveform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blurhash => $composableBuilder(
    column: $table.blurhash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnail => $composableBuilder(
    column: $table.thumbnail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transfer => $composableBuilder(
    column: $table.transfer,
    builder: (column) => ColumnOrderings(column),
  );

  $$MessagesTableOrderingComposer get messageRowid {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$HelixDb, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<Uint8List> get mediaKey =>
      $composableBuilder(column: $table.mediaKey, builder: (column) => column);

  GeneratedColumn<Uint8List> get digest =>
      $composableBuilder(column: $table.digest, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get waveform =>
      $composableBuilder(column: $table.waveform, builder: (column) => column);

  GeneratedColumn<String> get blurhash =>
      $composableBuilder(column: $table.blurhash, builder: (column) => column);

  GeneratedColumn<String> get caption =>
      $composableBuilder(column: $table.caption, builder: (column) => column);

  GeneratedColumn<String> get thumbnail =>
      $composableBuilder(column: $table.thumbnail, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AttachmentTransfer, String> get transfer =>
      $composableBuilder(column: $table.transfer, builder: (column) => column);

  $$MessagesTableAnnotationComposer get messageRowid {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> transferJobsRefs<T extends Object>(
    Expression<T> Function($$TransferJobsTableAnnotationComposer a) f,
  ) {
    final $$TransferJobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transferJobs,
      getReferencedColumn: (t) => t.attachmentRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransferJobsTableAnnotationComposer(
            $db: $db,
            $table: $db.transferJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AttachmentsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $AttachmentsTable,
          AttachmentRow,
          $$AttachmentsTableFilterComposer,
          $$AttachmentsTableOrderingComposer,
          $$AttachmentsTableAnnotationComposer,
          $$AttachmentsTableCreateCompanionBuilder,
          $$AttachmentsTableUpdateCompanionBuilder,
          (AttachmentRow, $$AttachmentsTableReferences),
          AttachmentRow,
          PrefetchHooks Function({bool messageRowid, bool transferJobsRefs})
        > {
  $$AttachmentsTableTableManager(_$HelixDb db, $AttachmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> messageRowid = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> mediaId = const Value.absent(),
                Value<Uint8List> mediaKey = const Value.absent(),
                Value<Uint8List> digest = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<Uint8List?> waveform = const Value.absent(),
                Value<String?> blurhash = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<String?> thumbnail = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<AttachmentTransfer> transfer = const Value.absent(),
              }) => AttachmentsCompanion(
                id: id,
                messageRowid: messageRowid,
                position: position,
                kind: kind,
                mediaId: mediaId,
                mediaKey: mediaKey,
                digest: digest,
                mime: mime,
                size: size,
                name: name,
                width: width,
                height: height,
                durationMs: durationMs,
                waveform: waveform,
                blurhash: blurhash,
                caption: caption,
                thumbnail: thumbnail,
                thumbnailPath: thumbnailPath,
                localPath: localPath,
                transfer: transfer,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int messageRowid,
                required int position,
                required String kind,
                required String mediaId,
                required Uint8List mediaKey,
                required Uint8List digest,
                required String mime,
                required int size,
                Value<String?> name = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<Uint8List?> waveform = const Value.absent(),
                Value<String?> blurhash = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<String?> thumbnail = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                required AttachmentTransfer transfer,
              }) => AttachmentsCompanion.insert(
                id: id,
                messageRowid: messageRowid,
                position: position,
                kind: kind,
                mediaId: mediaId,
                mediaKey: mediaKey,
                digest: digest,
                mime: mime,
                size: size,
                name: name,
                width: width,
                height: height,
                durationMs: durationMs,
                waveform: waveform,
                blurhash: blurhash,
                caption: caption,
                thumbnail: thumbnail,
                thumbnailPath: thumbnailPath,
                localPath: localPath,
                transfer: transfer,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AttachmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({messageRowid = false, transferJobsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (transferJobsRefs) db.transferJobs,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (messageRowid) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.messageRowid,
                                    referencedTable:
                                        $$AttachmentsTableReferences
                                            ._messageRowidTable(db),
                                    referencedColumn:
                                        $$AttachmentsTableReferences
                                            ._messageRowidTable(db)
                                            .localRowid,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (transferJobsRefs)
                        await $_getPrefetchedData<
                          AttachmentRow,
                          $AttachmentsTable,
                          TransferRow
                        >(
                          currentTable: table,
                          referencedTable: $$AttachmentsTableReferences
                              ._transferJobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AttachmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).transferJobsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.attachmentRowid == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $AttachmentsTable,
      AttachmentRow,
      $$AttachmentsTableFilterComposer,
      $$AttachmentsTableOrderingComposer,
      $$AttachmentsTableAnnotationComposer,
      $$AttachmentsTableCreateCompanionBuilder,
      $$AttachmentsTableUpdateCompanionBuilder,
      (AttachmentRow, $$AttachmentsTableReferences),
      AttachmentRow,
      PrefetchHooks Function({bool messageRowid, bool transferJobsRefs})
    >;
typedef $$ConversationMembersTableCreateCompanionBuilder =
    ConversationMembersCompanion Function({
      required String conversationId,
      required String accountId,
      Value<DateTime?> joinedAt,
      Value<int> rowid,
    });
typedef $$ConversationMembersTableUpdateCompanionBuilder =
    ConversationMembersCompanion Function({
      Value<String> conversationId,
      Value<String> accountId,
      Value<DateTime?> joinedAt,
      Value<int> rowid,
    });

final class $$ConversationMembersTableReferences
    extends
        BaseReferences<
          _$HelixDb,
          $ConversationMembersTable,
          ConversationMemberRow
        > {
  $$ConversationMembersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ConversationsTable _conversationIdTable(_$HelixDb db) => db
      .conversations
      .createAlias('conversation_members__conversation_id__conversations__id');

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ConversationMembersTableFilterComposer
    extends Composer<_$HelixDb, $ConversationMembersTable> {
  $$ConversationMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get joinedAt =>
      $composableBuilder(
        column: $table.joinedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationMembersTableOrderingComposer
    extends Composer<_$HelixDb, $ConversationMembersTable> {
  $$ConversationMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedAt => $composableBuilder(
    column: $table.joinedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationMembersTableAnnotationComposer
    extends Composer<_$HelixDb, $ConversationMembersTable> {
  $$ConversationMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get joinedAt =>
      $composableBuilder(column: $table.joinedAt, builder: (column) => column);

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationMembersTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $ConversationMembersTable,
          ConversationMemberRow,
          $$ConversationMembersTableFilterComposer,
          $$ConversationMembersTableOrderingComposer,
          $$ConversationMembersTableAnnotationComposer,
          $$ConversationMembersTableCreateCompanionBuilder,
          $$ConversationMembersTableUpdateCompanionBuilder,
          (ConversationMemberRow, $$ConversationMembersTableReferences),
          ConversationMemberRow,
          PrefetchHooks Function({bool conversationId})
        > {
  $$ConversationMembersTableTableManager(
    _$HelixDb db,
    $ConversationMembersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationMembersTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ConversationMembersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<DateTime?> joinedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationMembersCompanion(
                conversationId: conversationId,
                accountId: accountId,
                joinedAt: joinedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                required String accountId,
                Value<DateTime?> joinedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationMembersCompanion.insert(
                conversationId: conversationId,
                accountId: accountId,
                joinedAt: joinedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ConversationMembersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationId,
                                referencedTable:
                                    $$ConversationMembersTableReferences
                                        ._conversationIdTable(db),
                                referencedColumn:
                                    $$ConversationMembersTableReferences
                                        ._conversationIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ConversationMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $ConversationMembersTable,
      ConversationMemberRow,
      $$ConversationMembersTableFilterComposer,
      $$ConversationMembersTableOrderingComposer,
      $$ConversationMembersTableAnnotationComposer,
      $$ConversationMembersTableCreateCompanionBuilder,
      $$ConversationMembersTableUpdateCompanionBuilder,
      (ConversationMemberRow, $$ConversationMembersTableReferences),
      ConversationMemberRow,
      PrefetchHooks Function({bool conversationId})
    >;
typedef $$SelfAccountTableCreateCompanionBuilder =
    SelfAccountCompanion Function({
      Value<int> id,
      required String accountId,
      required String deviceId,
      required String serverDomain,
      Value<String?> helixName,
      Value<String?> phoneNumber,
      Value<String?> profileName,
      Value<Uint8List?> profileKey,
      Value<int> profileVersion,
      required DateTime registeredAt,
    });
typedef $$SelfAccountTableUpdateCompanionBuilder =
    SelfAccountCompanion Function({
      Value<int> id,
      Value<String> accountId,
      Value<String> deviceId,
      Value<String> serverDomain,
      Value<String?> helixName,
      Value<String?> phoneNumber,
      Value<String?> profileName,
      Value<Uint8List?> profileKey,
      Value<int> profileVersion,
      Value<DateTime> registeredAt,
    });

class $$SelfAccountTableFilterComposer
    extends Composer<_$HelixDb, $SelfAccountTable> {
  $$SelfAccountTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverDomain => $composableBuilder(
    column: $table.serverDomain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get helixName => $composableBuilder(
    column: $table.helixName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get profileKey => $composableBuilder(
    column: $table.profileKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get registeredAt =>
      $composableBuilder(
        column: $table.registeredAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SelfAccountTableOrderingComposer
    extends Composer<_$HelixDb, $SelfAccountTable> {
  $$SelfAccountTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverDomain => $composableBuilder(
    column: $table.serverDomain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get helixName => $composableBuilder(
    column: $table.helixName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get profileKey => $composableBuilder(
    column: $table.profileKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get registeredAt => $composableBuilder(
    column: $table.registeredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SelfAccountTableAnnotationComposer
    extends Composer<_$HelixDb, $SelfAccountTable> {
  $$SelfAccountTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get serverDomain => $composableBuilder(
    column: $table.serverDomain,
    builder: (column) => column,
  );

  GeneratedColumn<String> get helixName =>
      $composableBuilder(column: $table.helixName, builder: (column) => column);

  GeneratedColumn<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get profileKey => $composableBuilder(
    column: $table.profileKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get registeredAt =>
      $composableBuilder(
        column: $table.registeredAt,
        builder: (column) => column,
      );
}

class $$SelfAccountTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $SelfAccountTable,
          SelfAccountRow,
          $$SelfAccountTableFilterComposer,
          $$SelfAccountTableOrderingComposer,
          $$SelfAccountTableAnnotationComposer,
          $$SelfAccountTableCreateCompanionBuilder,
          $$SelfAccountTableUpdateCompanionBuilder,
          (
            SelfAccountRow,
            BaseReferences<_$HelixDb, $SelfAccountTable, SelfAccountRow>,
          ),
          SelfAccountRow,
          PrefetchHooks Function()
        > {
  $$SelfAccountTableTableManager(_$HelixDb db, $SelfAccountTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SelfAccountTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SelfAccountTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SelfAccountTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> serverDomain = const Value.absent(),
                Value<String?> helixName = const Value.absent(),
                Value<String?> phoneNumber = const Value.absent(),
                Value<String?> profileName = const Value.absent(),
                Value<Uint8List?> profileKey = const Value.absent(),
                Value<int> profileVersion = const Value.absent(),
                Value<DateTime> registeredAt = const Value.absent(),
              }) => SelfAccountCompanion(
                id: id,
                accountId: accountId,
                deviceId: deviceId,
                serverDomain: serverDomain,
                helixName: helixName,
                phoneNumber: phoneNumber,
                profileName: profileName,
                profileKey: profileKey,
                profileVersion: profileVersion,
                registeredAt: registeredAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String accountId,
                required String deviceId,
                required String serverDomain,
                Value<String?> helixName = const Value.absent(),
                Value<String?> phoneNumber = const Value.absent(),
                Value<String?> profileName = const Value.absent(),
                Value<Uint8List?> profileKey = const Value.absent(),
                Value<int> profileVersion = const Value.absent(),
                required DateTime registeredAt,
              }) => SelfAccountCompanion.insert(
                id: id,
                accountId: accountId,
                deviceId: deviceId,
                serverDomain: serverDomain,
                helixName: helixName,
                phoneNumber: phoneNumber,
                profileName: profileName,
                profileKey: profileKey,
                profileVersion: profileVersion,
                registeredAt: registeredAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SelfAccountTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $SelfAccountTable,
      SelfAccountRow,
      $$SelfAccountTableFilterComposer,
      $$SelfAccountTableOrderingComposer,
      $$SelfAccountTableAnnotationComposer,
      $$SelfAccountTableCreateCompanionBuilder,
      $$SelfAccountTableUpdateCompanionBuilder,
      (
        SelfAccountRow,
        BaseReferences<_$HelixDb, $SelfAccountTable, SelfAccountRow>,
      ),
      SelfAccountRow,
      PrefetchHooks Function()
    >;
typedef $$SelfDevicesTableCreateCompanionBuilder =
    SelfDevicesCompanion Function({
      required String deviceId,
      Value<String?> name,
      Value<String?> platform,
      Value<DateTime?> linkedAt,
      Value<DateTime?> lastActiveAt,
      Value<bool> isThisDevice,
      Value<int> rowid,
    });
typedef $$SelfDevicesTableUpdateCompanionBuilder =
    SelfDevicesCompanion Function({
      Value<String> deviceId,
      Value<String?> name,
      Value<String?> platform,
      Value<DateTime?> linkedAt,
      Value<DateTime?> lastActiveAt,
      Value<bool> isThisDevice,
      Value<int> rowid,
    });

class $$SelfDevicesTableFilterComposer
    extends Composer<_$HelixDb, $SelfDevicesTable> {
  $$SelfDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get linkedAt =>
      $composableBuilder(
        column: $table.linkedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get lastActiveAt =>
      $composableBuilder(
        column: $table.lastActiveAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get isThisDevice => $composableBuilder(
    column: $table.isThisDevice,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SelfDevicesTableOrderingComposer
    extends Composer<_$HelixDb, $SelfDevicesTable> {
  $$SelfDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get linkedAt => $composableBuilder(
    column: $table.linkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastActiveAt => $composableBuilder(
    column: $table.lastActiveAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isThisDevice => $composableBuilder(
    column: $table.isThisDevice,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SelfDevicesTableAnnotationComposer
    extends Composer<_$HelixDb, $SelfDevicesTable> {
  $$SelfDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get linkedAt =>
      $composableBuilder(column: $table.linkedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastActiveAt =>
      $composableBuilder(
        column: $table.lastActiveAt,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get isThisDevice => $composableBuilder(
    column: $table.isThisDevice,
    builder: (column) => column,
  );
}

class $$SelfDevicesTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $SelfDevicesTable,
          SelfDeviceRow,
          $$SelfDevicesTableFilterComposer,
          $$SelfDevicesTableOrderingComposer,
          $$SelfDevicesTableAnnotationComposer,
          $$SelfDevicesTableCreateCompanionBuilder,
          $$SelfDevicesTableUpdateCompanionBuilder,
          (
            SelfDeviceRow,
            BaseReferences<_$HelixDb, $SelfDevicesTable, SelfDeviceRow>,
          ),
          SelfDeviceRow,
          PrefetchHooks Function()
        > {
  $$SelfDevicesTableTableManager(_$HelixDb db, $SelfDevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SelfDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SelfDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SelfDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> platform = const Value.absent(),
                Value<DateTime?> linkedAt = const Value.absent(),
                Value<DateTime?> lastActiveAt = const Value.absent(),
                Value<bool> isThisDevice = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SelfDevicesCompanion(
                deviceId: deviceId,
                name: name,
                platform: platform,
                linkedAt: linkedAt,
                lastActiveAt: lastActiveAt,
                isThisDevice: isThisDevice,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                Value<String?> name = const Value.absent(),
                Value<String?> platform = const Value.absent(),
                Value<DateTime?> linkedAt = const Value.absent(),
                Value<DateTime?> lastActiveAt = const Value.absent(),
                Value<bool> isThisDevice = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SelfDevicesCompanion.insert(
                deviceId: deviceId,
                name: name,
                platform: platform,
                linkedAt: linkedAt,
                lastActiveAt: lastActiveAt,
                isThisDevice: isThisDevice,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SelfDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $SelfDevicesTable,
      SelfDeviceRow,
      $$SelfDevicesTableFilterComposer,
      $$SelfDevicesTableOrderingComposer,
      $$SelfDevicesTableAnnotationComposer,
      $$SelfDevicesTableCreateCompanionBuilder,
      $$SelfDevicesTableUpdateCompanionBuilder,
      (
        SelfDeviceRow,
        BaseReferences<_$HelixDb, $SelfDevicesTable, SelfDeviceRow>,
      ),
      SelfDeviceRow,
      PrefetchHooks Function()
    >;
typedef $$PeopleTableCreateCompanionBuilder =
    PeopleCompanion Function({
      required String accountId,
      Value<String?> helixName,
      Value<String?> phoneNumber,
      Value<String?> phoneHash,
      Value<String?> phonebookName,
      Value<String?> nickname,
      Value<String?> profileName,
      Value<Uint8List?> profileKey,
      Value<int?> profileVersion,
      Value<Uint8List?> avatarBlob,
      Value<Uint8List?> identityKey,
      Value<bool> identityVerified,
      Value<DateTime?> identityChangedAt,
      Value<bool> blocked,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PeopleTableUpdateCompanionBuilder =
    PeopleCompanion Function({
      Value<String> accountId,
      Value<String?> helixName,
      Value<String?> phoneNumber,
      Value<String?> phoneHash,
      Value<String?> phonebookName,
      Value<String?> nickname,
      Value<String?> profileName,
      Value<Uint8List?> profileKey,
      Value<int?> profileVersion,
      Value<Uint8List?> avatarBlob,
      Value<Uint8List?> identityKey,
      Value<bool> identityVerified,
      Value<DateTime?> identityChangedAt,
      Value<bool> blocked,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PeopleTableFilterComposer extends Composer<_$HelixDb, $PeopleTable> {
  $$PeopleTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get helixName => $composableBuilder(
    column: $table.helixName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneHash => $composableBuilder(
    column: $table.phoneHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phonebookName => $composableBuilder(
    column: $table.phonebookName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get profileKey => $composableBuilder(
    column: $table.profileKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get avatarBlob => $composableBuilder(
    column: $table.avatarBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get identityVerified => $composableBuilder(
    column: $table.identityVerified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int>
  get identityChangedAt => $composableBuilder(
    column: $table.identityChangedAt,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get blocked => $composableBuilder(
    column: $table.blocked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$PeopleTableOrderingComposer extends Composer<_$HelixDb, $PeopleTable> {
  $$PeopleTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get helixName => $composableBuilder(
    column: $table.helixName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneHash => $composableBuilder(
    column: $table.phoneHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phonebookName => $composableBuilder(
    column: $table.phonebookName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get profileKey => $composableBuilder(
    column: $table.profileKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get avatarBlob => $composableBuilder(
    column: $table.avatarBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get identityVerified => $composableBuilder(
    column: $table.identityVerified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get identityChangedAt => $composableBuilder(
    column: $table.identityChangedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get blocked => $composableBuilder(
    column: $table.blocked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeopleTableAnnotationComposer
    extends Composer<_$HelixDb, $PeopleTable> {
  $$PeopleTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get helixName =>
      $composableBuilder(column: $table.helixName, builder: (column) => column);

  GeneratedColumn<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get phoneHash =>
      $composableBuilder(column: $table.phoneHash, builder: (column) => column);

  GeneratedColumn<String> get phonebookName => $composableBuilder(
    column: $table.phonebookName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get profileKey => $composableBuilder(
    column: $table.profileKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get avatarBlob => $composableBuilder(
    column: $table.avatarBlob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get identityVerified => $composableBuilder(
    column: $table.identityVerified,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get identityChangedAt =>
      $composableBuilder(
        column: $table.identityChangedAt,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get blocked =>
      $composableBuilder(column: $table.blocked, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PeopleTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $PeopleTable,
          PersonRow,
          $$PeopleTableFilterComposer,
          $$PeopleTableOrderingComposer,
          $$PeopleTableAnnotationComposer,
          $$PeopleTableCreateCompanionBuilder,
          $$PeopleTableUpdateCompanionBuilder,
          (PersonRow, BaseReferences<_$HelixDb, $PeopleTable, PersonRow>),
          PersonRow,
          PrefetchHooks Function()
        > {
  $$PeopleTableTableManager(_$HelixDb db, $PeopleTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeopleTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeopleTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeopleTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String?> helixName = const Value.absent(),
                Value<String?> phoneNumber = const Value.absent(),
                Value<String?> phoneHash = const Value.absent(),
                Value<String?> phonebookName = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<String?> profileName = const Value.absent(),
                Value<Uint8List?> profileKey = const Value.absent(),
                Value<int?> profileVersion = const Value.absent(),
                Value<Uint8List?> avatarBlob = const Value.absent(),
                Value<Uint8List?> identityKey = const Value.absent(),
                Value<bool> identityVerified = const Value.absent(),
                Value<DateTime?> identityChangedAt = const Value.absent(),
                Value<bool> blocked = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeopleCompanion(
                accountId: accountId,
                helixName: helixName,
                phoneNumber: phoneNumber,
                phoneHash: phoneHash,
                phonebookName: phonebookName,
                nickname: nickname,
                profileName: profileName,
                profileKey: profileKey,
                profileVersion: profileVersion,
                avatarBlob: avatarBlob,
                identityKey: identityKey,
                identityVerified: identityVerified,
                identityChangedAt: identityChangedAt,
                blocked: blocked,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                Value<String?> helixName = const Value.absent(),
                Value<String?> phoneNumber = const Value.absent(),
                Value<String?> phoneHash = const Value.absent(),
                Value<String?> phonebookName = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<String?> profileName = const Value.absent(),
                Value<Uint8List?> profileKey = const Value.absent(),
                Value<int?> profileVersion = const Value.absent(),
                Value<Uint8List?> avatarBlob = const Value.absent(),
                Value<Uint8List?> identityKey = const Value.absent(),
                Value<bool> identityVerified = const Value.absent(),
                Value<DateTime?> identityChangedAt = const Value.absent(),
                Value<bool> blocked = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PeopleCompanion.insert(
                accountId: accountId,
                helixName: helixName,
                phoneNumber: phoneNumber,
                phoneHash: phoneHash,
                phonebookName: phonebookName,
                nickname: nickname,
                profileName: profileName,
                profileKey: profileKey,
                profileVersion: profileVersion,
                avatarBlob: avatarBlob,
                identityKey: identityKey,
                identityVerified: identityVerified,
                identityChangedAt: identityChangedAt,
                blocked: blocked,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeopleTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $PeopleTable,
      PersonRow,
      $$PeopleTableFilterComposer,
      $$PeopleTableOrderingComposer,
      $$PeopleTableAnnotationComposer,
      $$PeopleTableCreateCompanionBuilder,
      $$PeopleTableUpdateCompanionBuilder,
      (PersonRow, BaseReferences<_$HelixDb, $PeopleTable, PersonRow>),
      PersonRow,
      PrefetchHooks Function()
    >;
typedef $$PersonDevicesTableCreateCompanionBuilder =
    PersonDevicesCompanion Function({
      required String accountId,
      required String deviceId,
      required Uint8List identityKey,
      required Uint8List signingKey,
      Value<Uint8List?> certificate,
      required DeviceTrust trust,
      required DateTime firstSeenAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PersonDevicesTableUpdateCompanionBuilder =
    PersonDevicesCompanion Function({
      Value<String> accountId,
      Value<String> deviceId,
      Value<Uint8List> identityKey,
      Value<Uint8List> signingKey,
      Value<Uint8List?> certificate,
      Value<DeviceTrust> trust,
      Value<DateTime> firstSeenAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PersonDevicesTableFilterComposer
    extends Composer<_$HelixDb, $PersonDevicesTable> {
  $$PersonDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get signingKey => $composableBuilder(
    column: $table.signingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get certificate => $composableBuilder(
    column: $table.certificate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DeviceTrust, DeviceTrust, String> get trust =>
      $composableBuilder(
        column: $table.trust,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get firstSeenAt =>
      $composableBuilder(
        column: $table.firstSeenAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$PersonDevicesTableOrderingComposer
    extends Composer<_$HelixDb, $PersonDevicesTable> {
  $$PersonDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get signingKey => $composableBuilder(
    column: $table.signingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get certificate => $composableBuilder(
    column: $table.certificate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trust => $composableBuilder(
    column: $table.trust,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonDevicesTableAnnotationComposer
    extends Composer<_$HelixDb, $PersonDevicesTable> {
  $$PersonDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get signingKey => $composableBuilder(
    column: $table.signingKey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get certificate => $composableBuilder(
    column: $table.certificate,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DeviceTrust, String> get trust =>
      $composableBuilder(column: $table.trust, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get firstSeenAt =>
      $composableBuilder(
        column: $table.firstSeenAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PersonDevicesTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $PersonDevicesTable,
          PersonDeviceRow,
          $$PersonDevicesTableFilterComposer,
          $$PersonDevicesTableOrderingComposer,
          $$PersonDevicesTableAnnotationComposer,
          $$PersonDevicesTableCreateCompanionBuilder,
          $$PersonDevicesTableUpdateCompanionBuilder,
          (
            PersonDeviceRow,
            BaseReferences<_$HelixDb, $PersonDevicesTable, PersonDeviceRow>,
          ),
          PersonDeviceRow,
          PrefetchHooks Function()
        > {
  $$PersonDevicesTableTableManager(_$HelixDb db, $PersonDevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<Uint8List> identityKey = const Value.absent(),
                Value<Uint8List> signingKey = const Value.absent(),
                Value<Uint8List?> certificate = const Value.absent(),
                Value<DeviceTrust> trust = const Value.absent(),
                Value<DateTime> firstSeenAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonDevicesCompanion(
                accountId: accountId,
                deviceId: deviceId,
                identityKey: identityKey,
                signingKey: signingKey,
                certificate: certificate,
                trust: trust,
                firstSeenAt: firstSeenAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String deviceId,
                required Uint8List identityKey,
                required Uint8List signingKey,
                Value<Uint8List?> certificate = const Value.absent(),
                required DeviceTrust trust,
                required DateTime firstSeenAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PersonDevicesCompanion.insert(
                accountId: accountId,
                deviceId: deviceId,
                identityKey: identityKey,
                signingKey: signingKey,
                certificate: certificate,
                trust: trust,
                firstSeenAt: firstSeenAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PersonDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $PersonDevicesTable,
      PersonDeviceRow,
      $$PersonDevicesTableFilterComposer,
      $$PersonDevicesTableOrderingComposer,
      $$PersonDevicesTableAnnotationComposer,
      $$PersonDevicesTableCreateCompanionBuilder,
      $$PersonDevicesTableUpdateCompanionBuilder,
      (
        PersonDeviceRow,
        BaseReferences<_$HelixDb, $PersonDevicesTable, PersonDeviceRow>,
      ),
      PersonDeviceRow,
      PrefetchHooks Function()
    >;
typedef $$IdentityTableCreateCompanionBuilder =
    IdentityCompanion Function({
      Value<int> id,
      required String accountId,
      required String deviceId,
      required Uint8List aikPublic,
      required Uint8List aikPrivate,
      required Uint8List dikPublic,
      required Uint8List dikPrivate,
      required Uint8List dskPublic,
      required Uint8List dskPrivate,
      required Uint8List deviceCertificate,
      required DateTime createdAt,
    });
typedef $$IdentityTableUpdateCompanionBuilder =
    IdentityCompanion Function({
      Value<int> id,
      Value<String> accountId,
      Value<String> deviceId,
      Value<Uint8List> aikPublic,
      Value<Uint8List> aikPrivate,
      Value<Uint8List> dikPublic,
      Value<Uint8List> dikPrivate,
      Value<Uint8List> dskPublic,
      Value<Uint8List> dskPrivate,
      Value<Uint8List> deviceCertificate,
      Value<DateTime> createdAt,
    });

class $$IdentityTableFilterComposer
    extends Composer<_$HelixDb, $IdentityTable> {
  $$IdentityTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get aikPublic => $composableBuilder(
    column: $table.aikPublic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get aikPrivate => $composableBuilder(
    column: $table.aikPrivate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get dikPublic => $composableBuilder(
    column: $table.dikPublic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get dikPrivate => $composableBuilder(
    column: $table.dikPrivate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get dskPublic => $composableBuilder(
    column: $table.dskPublic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get dskPrivate => $composableBuilder(
    column: $table.dskPrivate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get deviceCertificate => $composableBuilder(
    column: $table.deviceCertificate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$IdentityTableOrderingComposer
    extends Composer<_$HelixDb, $IdentityTable> {
  $$IdentityTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get aikPublic => $composableBuilder(
    column: $table.aikPublic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get aikPrivate => $composableBuilder(
    column: $table.aikPrivate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get dikPublic => $composableBuilder(
    column: $table.dikPublic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get dikPrivate => $composableBuilder(
    column: $table.dikPrivate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get dskPublic => $composableBuilder(
    column: $table.dskPublic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get dskPrivate => $composableBuilder(
    column: $table.dskPrivate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get deviceCertificate => $composableBuilder(
    column: $table.deviceCertificate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IdentityTableAnnotationComposer
    extends Composer<_$HelixDb, $IdentityTable> {
  $$IdentityTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<Uint8List> get aikPublic =>
      $composableBuilder(column: $table.aikPublic, builder: (column) => column);

  GeneratedColumn<Uint8List> get aikPrivate => $composableBuilder(
    column: $table.aikPrivate,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get dikPublic =>
      $composableBuilder(column: $table.dikPublic, builder: (column) => column);

  GeneratedColumn<Uint8List> get dikPrivate => $composableBuilder(
    column: $table.dikPrivate,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get dskPublic =>
      $composableBuilder(column: $table.dskPublic, builder: (column) => column);

  GeneratedColumn<Uint8List> get dskPrivate => $composableBuilder(
    column: $table.dskPrivate,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get deviceCertificate => $composableBuilder(
    column: $table.deviceCertificate,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$IdentityTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $IdentityTable,
          IdentityRow,
          $$IdentityTableFilterComposer,
          $$IdentityTableOrderingComposer,
          $$IdentityTableAnnotationComposer,
          $$IdentityTableCreateCompanionBuilder,
          $$IdentityTableUpdateCompanionBuilder,
          (IdentityRow, BaseReferences<_$HelixDb, $IdentityTable, IdentityRow>),
          IdentityRow,
          PrefetchHooks Function()
        > {
  $$IdentityTableTableManager(_$HelixDb db, $IdentityTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentityTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IdentityTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IdentityTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<Uint8List> aikPublic = const Value.absent(),
                Value<Uint8List> aikPrivate = const Value.absent(),
                Value<Uint8List> dikPublic = const Value.absent(),
                Value<Uint8List> dikPrivate = const Value.absent(),
                Value<Uint8List> dskPublic = const Value.absent(),
                Value<Uint8List> dskPrivate = const Value.absent(),
                Value<Uint8List> deviceCertificate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => IdentityCompanion(
                id: id,
                accountId: accountId,
                deviceId: deviceId,
                aikPublic: aikPublic,
                aikPrivate: aikPrivate,
                dikPublic: dikPublic,
                dikPrivate: dikPrivate,
                dskPublic: dskPublic,
                dskPrivate: dskPrivate,
                deviceCertificate: deviceCertificate,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String accountId,
                required String deviceId,
                required Uint8List aikPublic,
                required Uint8List aikPrivate,
                required Uint8List dikPublic,
                required Uint8List dikPrivate,
                required Uint8List dskPublic,
                required Uint8List dskPrivate,
                required Uint8List deviceCertificate,
                required DateTime createdAt,
              }) => IdentityCompanion.insert(
                id: id,
                accountId: accountId,
                deviceId: deviceId,
                aikPublic: aikPublic,
                aikPrivate: aikPrivate,
                dikPublic: dikPublic,
                dikPrivate: dikPrivate,
                dskPublic: dskPublic,
                dskPrivate: dskPrivate,
                deviceCertificate: deviceCertificate,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IdentityTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $IdentityTable,
      IdentityRow,
      $$IdentityTableFilterComposer,
      $$IdentityTableOrderingComposer,
      $$IdentityTableAnnotationComposer,
      $$IdentityTableCreateCompanionBuilder,
      $$IdentityTableUpdateCompanionBuilder,
      (IdentityRow, BaseReferences<_$HelixDb, $IdentityTable, IdentityRow>),
      IdentityRow,
      PrefetchHooks Function()
    >;
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String peerAccountId,
      required String peerDeviceId,
      required int slot,
      required Uint8List state,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> peerAccountId,
      Value<String> peerDeviceId,
      Value<int> slot,
      Value<Uint8List> state,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SessionsTableFilterComposer
    extends Composer<_$HelixDb, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerAccountId => $composableBuilder(
    column: $table.peerAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SessionsTableOrderingComposer
    extends Composer<_$HelixDb, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerAccountId => $composableBuilder(
    column: $table.peerAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$HelixDb, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerAccountId => $composableBuilder(
    column: $table.peerAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<Uint8List> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $SessionsTable,
          SessionRow,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (SessionRow, BaseReferences<_$HelixDb, $SessionsTable, SessionRow>),
          SessionRow,
          PrefetchHooks Function()
        > {
  $$SessionsTableTableManager(_$HelixDb db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> peerAccountId = const Value.absent(),
                Value<String> peerDeviceId = const Value.absent(),
                Value<int> slot = const Value.absent(),
                Value<Uint8List> state = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                peerAccountId: peerAccountId,
                peerDeviceId: peerDeviceId,
                slot: slot,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerAccountId,
                required String peerDeviceId,
                required int slot,
                required Uint8List state,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                peerAccountId: peerAccountId,
                peerDeviceId: peerDeviceId,
                slot: slot,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $SessionsTable,
      SessionRow,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (SessionRow, BaseReferences<_$HelixDb, $SessionsTable, SessionRow>),
      SessionRow,
      PrefetchHooks Function()
    >;
typedef $$PrekeysTableCreateCompanionBuilder =
    PrekeysCompanion Function({
      required PrekeyKind kind,
      required int keyId,
      required Uint8List publicKey,
      required Uint8List privateKey,
      Value<Uint8List?> signature,
      required DateTime createdAt,
      Value<DateTime?> retiredAt,
      Value<int> rowid,
    });
typedef $$PrekeysTableUpdateCompanionBuilder =
    PrekeysCompanion Function({
      Value<PrekeyKind> kind,
      Value<int> keyId,
      Value<Uint8List> publicKey,
      Value<Uint8List> privateKey,
      Value<Uint8List?> signature,
      Value<DateTime> createdAt,
      Value<DateTime?> retiredAt,
      Value<int> rowid,
    });

class $$PrekeysTableFilterComposer extends Composer<_$HelixDb, $PrekeysTable> {
  $$PrekeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<PrekeyKind, PrekeyKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get privateKey => $composableBuilder(
    column: $table.privateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get retiredAt =>
      $composableBuilder(
        column: $table.retiredAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$PrekeysTableOrderingComposer
    extends Composer<_$HelixDb, $PrekeysTable> {
  $$PrekeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get keyId => $composableBuilder(
    column: $table.keyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get privateKey => $composableBuilder(
    column: $table.privateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retiredAt => $composableBuilder(
    column: $table.retiredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PrekeysTableAnnotationComposer
    extends Composer<_$HelixDb, $PrekeysTable> {
  $$PrekeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<PrekeyKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get keyId =>
      $composableBuilder(column: $table.keyId, builder: (column) => column);

  GeneratedColumn<Uint8List> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<Uint8List> get privateKey => $composableBuilder(
    column: $table.privateKey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get retiredAt =>
      $composableBuilder(column: $table.retiredAt, builder: (column) => column);
}

class $$PrekeysTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $PrekeysTable,
          PrekeyRow,
          $$PrekeysTableFilterComposer,
          $$PrekeysTableOrderingComposer,
          $$PrekeysTableAnnotationComposer,
          $$PrekeysTableCreateCompanionBuilder,
          $$PrekeysTableUpdateCompanionBuilder,
          (PrekeyRow, BaseReferences<_$HelixDb, $PrekeysTable, PrekeyRow>),
          PrekeyRow,
          PrefetchHooks Function()
        > {
  $$PrekeysTableTableManager(_$HelixDb db, $PrekeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PrekeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PrekeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PrekeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<PrekeyKind> kind = const Value.absent(),
                Value<int> keyId = const Value.absent(),
                Value<Uint8List> publicKey = const Value.absent(),
                Value<Uint8List> privateKey = const Value.absent(),
                Value<Uint8List?> signature = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> retiredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PrekeysCompanion(
                kind: kind,
                keyId: keyId,
                publicKey: publicKey,
                privateKey: privateKey,
                signature: signature,
                createdAt: createdAt,
                retiredAt: retiredAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required PrekeyKind kind,
                required int keyId,
                required Uint8List publicKey,
                required Uint8List privateKey,
                Value<Uint8List?> signature = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> retiredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PrekeysCompanion.insert(
                kind: kind,
                keyId: keyId,
                publicKey: publicKey,
                privateKey: privateKey,
                signature: signature,
                createdAt: createdAt,
                retiredAt: retiredAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PrekeysTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $PrekeysTable,
      PrekeyRow,
      $$PrekeysTableFilterComposer,
      $$PrekeysTableOrderingComposer,
      $$PrekeysTableAnnotationComposer,
      $$PrekeysTableCreateCompanionBuilder,
      $$PrekeysTableUpdateCompanionBuilder,
      (PrekeyRow, BaseReferences<_$HelixDb, $PrekeysTable, PrekeyRow>),
      PrekeyRow,
      PrefetchHooks Function()
    >;
typedef $$SenderKeysTableCreateCompanionBuilder =
    SenderKeysCompanion Function({
      required String groupId,
      required String accountId,
      required String deviceId,
      required String distId,
      required Uint8List state,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SenderKeysTableUpdateCompanionBuilder =
    SenderKeysCompanion Function({
      Value<String> groupId,
      Value<String> accountId,
      Value<String> deviceId,
      Value<String> distId,
      Value<Uint8List> state,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SenderKeysTableFilterComposer
    extends Composer<_$HelixDb, $SenderKeysTable> {
  $$SenderKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get distId => $composableBuilder(
    column: $table.distId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SenderKeysTableOrderingComposer
    extends Composer<_$HelixDb, $SenderKeysTable> {
  $$SenderKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get distId => $composableBuilder(
    column: $table.distId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SenderKeysTableAnnotationComposer
    extends Composer<_$HelixDb, $SenderKeysTable> {
  $$SenderKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get distId =>
      $composableBuilder(column: $table.distId, builder: (column) => column);

  GeneratedColumn<Uint8List> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SenderKeysTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $SenderKeysTable,
          SenderKeyRow,
          $$SenderKeysTableFilterComposer,
          $$SenderKeysTableOrderingComposer,
          $$SenderKeysTableAnnotationComposer,
          $$SenderKeysTableCreateCompanionBuilder,
          $$SenderKeysTableUpdateCompanionBuilder,
          (
            SenderKeyRow,
            BaseReferences<_$HelixDb, $SenderKeysTable, SenderKeyRow>,
          ),
          SenderKeyRow,
          PrefetchHooks Function()
        > {
  $$SenderKeysTableTableManager(_$HelixDb db, $SenderKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SenderKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SenderKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SenderKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> distId = const Value.absent(),
                Value<Uint8List> state = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SenderKeysCompanion(
                groupId: groupId,
                accountId: accountId,
                deviceId: deviceId,
                distId: distId,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String accountId,
                required String deviceId,
                required String distId,
                required Uint8List state,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SenderKeysCompanion.insert(
                groupId: groupId,
                accountId: accountId,
                deviceId: deviceId,
                distId: distId,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SenderKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $SenderKeysTable,
      SenderKeyRow,
      $$SenderKeysTableFilterComposer,
      $$SenderKeysTableOrderingComposer,
      $$SenderKeysTableAnnotationComposer,
      $$SenderKeysTableCreateCompanionBuilder,
      $$SenderKeysTableUpdateCompanionBuilder,
      (SenderKeyRow, BaseReferences<_$HelixDb, $SenderKeysTable, SenderKeyRow>),
      SenderKeyRow,
      PrefetchHooks Function()
    >;
typedef $$InboxCursorTableCreateCompanionBuilder =
    InboxCursorCompanion Function({
      Value<int> id,
      Value<int> lastProcessedSeq,
      Value<int> lastAckedSeq,
      required DateTime updatedAt,
    });
typedef $$InboxCursorTableUpdateCompanionBuilder =
    InboxCursorCompanion Function({
      Value<int> id,
      Value<int> lastProcessedSeq,
      Value<int> lastAckedSeq,
      Value<DateTime> updatedAt,
    });

class $$InboxCursorTableFilterComposer
    extends Composer<_$HelixDb, $InboxCursorTable> {
  $$InboxCursorTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastProcessedSeq => $composableBuilder(
    column: $table.lastProcessedSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAckedSeq => $composableBuilder(
    column: $table.lastAckedSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$InboxCursorTableOrderingComposer
    extends Composer<_$HelixDb, $InboxCursorTable> {
  $$InboxCursorTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastProcessedSeq => $composableBuilder(
    column: $table.lastProcessedSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAckedSeq => $composableBuilder(
    column: $table.lastAckedSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InboxCursorTableAnnotationComposer
    extends Composer<_$HelixDb, $InboxCursorTable> {
  $$InboxCursorTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get lastProcessedSeq => $composableBuilder(
    column: $table.lastProcessedSeq,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastAckedSeq => $composableBuilder(
    column: $table.lastAckedSeq,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$InboxCursorTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $InboxCursorTable,
          InboxCursorRow,
          $$InboxCursorTableFilterComposer,
          $$InboxCursorTableOrderingComposer,
          $$InboxCursorTableAnnotationComposer,
          $$InboxCursorTableCreateCompanionBuilder,
          $$InboxCursorTableUpdateCompanionBuilder,
          (
            InboxCursorRow,
            BaseReferences<_$HelixDb, $InboxCursorTable, InboxCursorRow>,
          ),
          InboxCursorRow,
          PrefetchHooks Function()
        > {
  $$InboxCursorTableTableManager(_$HelixDb db, $InboxCursorTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InboxCursorTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InboxCursorTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InboxCursorTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> lastProcessedSeq = const Value.absent(),
                Value<int> lastAckedSeq = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => InboxCursorCompanion(
                id: id,
                lastProcessedSeq: lastProcessedSeq,
                lastAckedSeq: lastAckedSeq,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> lastProcessedSeq = const Value.absent(),
                Value<int> lastAckedSeq = const Value.absent(),
                required DateTime updatedAt,
              }) => InboxCursorCompanion.insert(
                id: id,
                lastProcessedSeq: lastProcessedSeq,
                lastAckedSeq: lastAckedSeq,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InboxCursorTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $InboxCursorTable,
      InboxCursorRow,
      $$InboxCursorTableFilterComposer,
      $$InboxCursorTableOrderingComposer,
      $$InboxCursorTableAnnotationComposer,
      $$InboxCursorTableCreateCompanionBuilder,
      $$InboxCursorTableUpdateCompanionBuilder,
      (
        InboxCursorRow,
        BaseReferences<_$HelixDb, $InboxCursorTable, InboxCursorRow>,
      ),
      InboxCursorRow,
      PrefetchHooks Function()
    >;
typedef $$ProcessedEnvelopesTableCreateCompanionBuilder =
    ProcessedEnvelopesCompanion Function({
      required String envelopeId,
      Value<String> senderDevice,
      Value<int?> seq,
      required EnvelopeOutcome outcome,
      required DateTime processedAt,
      Value<int> rowid,
    });
typedef $$ProcessedEnvelopesTableUpdateCompanionBuilder =
    ProcessedEnvelopesCompanion Function({
      Value<String> envelopeId,
      Value<String> senderDevice,
      Value<int?> seq,
      Value<EnvelopeOutcome> outcome,
      Value<DateTime> processedAt,
      Value<int> rowid,
    });

class $$ProcessedEnvelopesTableFilterComposer
    extends Composer<_$HelixDb, $ProcessedEnvelopesTable> {
  $$ProcessedEnvelopesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EnvelopeOutcome, EnvelopeOutcome, String>
  get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get processedAt =>
      $composableBuilder(
        column: $table.processedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$ProcessedEnvelopesTableOrderingComposer
    extends Composer<_$HelixDb, $ProcessedEnvelopesTable> {
  $$ProcessedEnvelopesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProcessedEnvelopesTableAnnotationComposer
    extends Composer<_$HelixDb, $ProcessedEnvelopesTable> {
  $$ProcessedEnvelopesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get envelopeId => $composableBuilder(
    column: $table.envelopeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EnvelopeOutcome, String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get processedAt =>
      $composableBuilder(
        column: $table.processedAt,
        builder: (column) => column,
      );
}

class $$ProcessedEnvelopesTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $ProcessedEnvelopesTable,
          ProcessedEnvelopeRow,
          $$ProcessedEnvelopesTableFilterComposer,
          $$ProcessedEnvelopesTableOrderingComposer,
          $$ProcessedEnvelopesTableAnnotationComposer,
          $$ProcessedEnvelopesTableCreateCompanionBuilder,
          $$ProcessedEnvelopesTableUpdateCompanionBuilder,
          (
            ProcessedEnvelopeRow,
            BaseReferences<
              _$HelixDb,
              $ProcessedEnvelopesTable,
              ProcessedEnvelopeRow
            >,
          ),
          ProcessedEnvelopeRow,
          PrefetchHooks Function()
        > {
  $$ProcessedEnvelopesTableTableManager(
    _$HelixDb db,
    $ProcessedEnvelopesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProcessedEnvelopesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProcessedEnvelopesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProcessedEnvelopesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> envelopeId = const Value.absent(),
                Value<String> senderDevice = const Value.absent(),
                Value<int?> seq = const Value.absent(),
                Value<EnvelopeOutcome> outcome = const Value.absent(),
                Value<DateTime> processedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProcessedEnvelopesCompanion(
                envelopeId: envelopeId,
                senderDevice: senderDevice,
                seq: seq,
                outcome: outcome,
                processedAt: processedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String envelopeId,
                Value<String> senderDevice = const Value.absent(),
                Value<int?> seq = const Value.absent(),
                required EnvelopeOutcome outcome,
                required DateTime processedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProcessedEnvelopesCompanion.insert(
                envelopeId: envelopeId,
                senderDevice: senderDevice,
                seq: seq,
                outcome: outcome,
                processedAt: processedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProcessedEnvelopesTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $ProcessedEnvelopesTable,
      ProcessedEnvelopeRow,
      $$ProcessedEnvelopesTableFilterComposer,
      $$ProcessedEnvelopesTableOrderingComposer,
      $$ProcessedEnvelopesTableAnnotationComposer,
      $$ProcessedEnvelopesTableCreateCompanionBuilder,
      $$ProcessedEnvelopesTableUpdateCompanionBuilder,
      (
        ProcessedEnvelopeRow,
        BaseReferences<
          _$HelixDb,
          $ProcessedEnvelopesTable,
          ProcessedEnvelopeRow
        >,
      ),
      ProcessedEnvelopeRow,
      PrefetchHooks Function()
    >;
typedef $$OutboxOpsTableCreateCompanionBuilder =
    OutboxOpsCompanion Function({
      Value<int> id,
      required String kind,
      Value<String?> conversationId,
      Value<int?> messageRowid,
      required String idempotencyKey,
      required String payload,
      required OutboxState state,
      Value<int> attempts,
      required DateTime nextAttemptAt,
      Value<DateTime?> leaseUntil,
      Value<String?> lastError,
      required DateTime createdAt,
    });
typedef $$OutboxOpsTableUpdateCompanionBuilder =
    OutboxOpsCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String?> conversationId,
      Value<int?> messageRowid,
      Value<String> idempotencyKey,
      Value<String> payload,
      Value<OutboxState> state,
      Value<int> attempts,
      Value<DateTime> nextAttemptAt,
      Value<DateTime?> leaseUntil,
      Value<String?> lastError,
      Value<DateTime> createdAt,
    });

final class $$OutboxOpsTableReferences
    extends BaseReferences<_$HelixDb, $OutboxOpsTable, OutboxOpRow> {
  $$OutboxOpsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConversationsTable _conversationIdTable(_$HelixDb db) => db
      .conversations
      .createAlias('outbox_ops__conversation_id__conversations__id');

  $$ConversationsTableProcessedTableManager? get conversationId {
    final $_column = $_itemColumn<String>('conversation_id');
    if ($_column == null) return null;
    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MessagesTable _messageRowidTable(_$HelixDb db) => db.messages
      .createAlias('outbox_ops__message_rowid__messages__local_rowid');

  $$MessagesTableProcessedTableManager? get messageRowid {
    final $_column = $_itemColumn<int>('message_rowid');
    if ($_column == null) return null;
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.localRowid.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageRowidTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutboxOpsTableFilterComposer
    extends Composer<_$HelixDb, $OutboxOpsTable> {
  $$OutboxOpsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<OutboxState, OutboxState, String> get state =>
      $composableBuilder(
        column: $table.state,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get nextAttemptAt =>
      $composableBuilder(
        column: $table.nextAttemptAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get leaseUntil =>
      $composableBuilder(
        column: $table.leaseUntil,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableFilterComposer get messageRowid {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxOpsTableOrderingComposer
    extends Composer<_$HelixDb, $OutboxOpsTable> {
  $$OutboxOpsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get leaseUntil => $composableBuilder(
    column: $table.leaseUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableOrderingComposer get messageRowid {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxOpsTableAnnotationComposer
    extends Composer<_$HelixDb, $OutboxOpsTable> {
  $$OutboxOpsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumnWithTypeConverter<OutboxState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get nextAttemptAt =>
      $composableBuilder(
        column: $table.nextAttemptAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get leaseUntil =>
      $composableBuilder(
        column: $table.leaseUntil,
        builder: (column) => column,
      );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableAnnotationComposer get messageRowid {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageRowid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.localRowid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxOpsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $OutboxOpsTable,
          OutboxOpRow,
          $$OutboxOpsTableFilterComposer,
          $$OutboxOpsTableOrderingComposer,
          $$OutboxOpsTableAnnotationComposer,
          $$OutboxOpsTableCreateCompanionBuilder,
          $$OutboxOpsTableUpdateCompanionBuilder,
          (OutboxOpRow, $$OutboxOpsTableReferences),
          OutboxOpRow,
          PrefetchHooks Function({bool conversationId, bool messageRowid})
        > {
  $$OutboxOpsTableTableManager(_$HelixDb db, $OutboxOpsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxOpsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxOpsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxOpsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> conversationId = const Value.absent(),
                Value<int?> messageRowid = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<OutboxState> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> nextAttemptAt = const Value.absent(),
                Value<DateTime?> leaseUntil = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => OutboxOpsCompanion(
                id: id,
                kind: kind,
                conversationId: conversationId,
                messageRowid: messageRowid,
                idempotencyKey: idempotencyKey,
                payload: payload,
                state: state,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                leaseUntil: leaseUntil,
                lastError: lastError,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                Value<String?> conversationId = const Value.absent(),
                Value<int?> messageRowid = const Value.absent(),
                required String idempotencyKey,
                required String payload,
                required OutboxState state,
                Value<int> attempts = const Value.absent(),
                required DateTime nextAttemptAt,
                Value<DateTime?> leaseUntil = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
              }) => OutboxOpsCompanion.insert(
                id: id,
                kind: kind,
                conversationId: conversationId,
                messageRowid: messageRowid,
                idempotencyKey: idempotencyKey,
                payload: payload,
                state: state,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                leaseUntil: leaseUntil,
                lastError: lastError,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OutboxOpsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({conversationId = false, messageRowid = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (conversationId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.conversationId,
                                    referencedTable: $$OutboxOpsTableReferences
                                        ._conversationIdTable(db),
                                    referencedColumn: $$OutboxOpsTableReferences
                                        ._conversationIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (messageRowid) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.messageRowid,
                                    referencedTable: $$OutboxOpsTableReferences
                                        ._messageRowidTable(db),
                                    referencedColumn: $$OutboxOpsTableReferences
                                        ._messageRowidTable(db)
                                        .localRowid,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$OutboxOpsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $OutboxOpsTable,
      OutboxOpRow,
      $$OutboxOpsTableFilterComposer,
      $$OutboxOpsTableOrderingComposer,
      $$OutboxOpsTableAnnotationComposer,
      $$OutboxOpsTableCreateCompanionBuilder,
      $$OutboxOpsTableUpdateCompanionBuilder,
      (OutboxOpRow, $$OutboxOpsTableReferences),
      OutboxOpRow,
      PrefetchHooks Function({bool conversationId, bool messageRowid})
    >;
typedef $$DeferredActionsTableCreateCompanionBuilder =
    DeferredActionsCompanion Function({
      Value<int> id,
      required String targetMessageId,
      required String targetAuthor,
      required String sender,
      Value<String?> senderDevice,
      required String kind,
      required String payload,
      required DateTime receivedAt,
      required DateTime expiresAt,
    });
typedef $$DeferredActionsTableUpdateCompanionBuilder =
    DeferredActionsCompanion Function({
      Value<int> id,
      Value<String> targetMessageId,
      Value<String> targetAuthor,
      Value<String> sender,
      Value<String?> senderDevice,
      Value<String> kind,
      Value<String> payload,
      Value<DateTime> receivedAt,
      Value<DateTime> expiresAt,
    });

class $$DeferredActionsTableFilterComposer
    extends Composer<_$HelixDb, $DeferredActionsTable> {
  $$DeferredActionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetMessageId => $composableBuilder(
    column: $table.targetMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetAuthor => $composableBuilder(
    column: $table.targetAuthor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get receivedAt =>
      $composableBuilder(
        column: $table.receivedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get expiresAt =>
      $composableBuilder(
        column: $table.expiresAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$DeferredActionsTableOrderingComposer
    extends Composer<_$HelixDb, $DeferredActionsTable> {
  $$DeferredActionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetMessageId => $composableBuilder(
    column: $table.targetMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetAuthor => $composableBuilder(
    column: $table.targetAuthor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeferredActionsTableAnnotationComposer
    extends Composer<_$HelixDb, $DeferredActionsTable> {
  $$DeferredActionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get targetMessageId => $composableBuilder(
    column: $table.targetMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetAuthor => $composableBuilder(
    column: $table.targetAuthor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => column);

  GeneratedColumn<String> get senderDevice => $composableBuilder(
    column: $table.senderDevice,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get receivedAt =>
      $composableBuilder(
        column: $table.receivedAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$DeferredActionsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $DeferredActionsTable,
          DeferredActionRow,
          $$DeferredActionsTableFilterComposer,
          $$DeferredActionsTableOrderingComposer,
          $$DeferredActionsTableAnnotationComposer,
          $$DeferredActionsTableCreateCompanionBuilder,
          $$DeferredActionsTableUpdateCompanionBuilder,
          (
            DeferredActionRow,
            BaseReferences<_$HelixDb, $DeferredActionsTable, DeferredActionRow>,
          ),
          DeferredActionRow,
          PrefetchHooks Function()
        > {
  $$DeferredActionsTableTableManager(_$HelixDb db, $DeferredActionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeferredActionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeferredActionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeferredActionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> targetMessageId = const Value.absent(),
                Value<String> targetAuthor = const Value.absent(),
                Value<String> sender = const Value.absent(),
                Value<String?> senderDevice = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
              }) => DeferredActionsCompanion(
                id: id,
                targetMessageId: targetMessageId,
                targetAuthor: targetAuthor,
                sender: sender,
                senderDevice: senderDevice,
                kind: kind,
                payload: payload,
                receivedAt: receivedAt,
                expiresAt: expiresAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String targetMessageId,
                required String targetAuthor,
                required String sender,
                Value<String?> senderDevice = const Value.absent(),
                required String kind,
                required String payload,
                required DateTime receivedAt,
                required DateTime expiresAt,
              }) => DeferredActionsCompanion.insert(
                id: id,
                targetMessageId: targetMessageId,
                targetAuthor: targetAuthor,
                sender: sender,
                senderDevice: senderDevice,
                kind: kind,
                payload: payload,
                receivedAt: receivedAt,
                expiresAt: expiresAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeferredActionsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $DeferredActionsTable,
      DeferredActionRow,
      $$DeferredActionsTableFilterComposer,
      $$DeferredActionsTableOrderingComposer,
      $$DeferredActionsTableAnnotationComposer,
      $$DeferredActionsTableCreateCompanionBuilder,
      $$DeferredActionsTableUpdateCompanionBuilder,
      (
        DeferredActionRow,
        BaseReferences<_$HelixDb, $DeferredActionsTable, DeferredActionRow>,
      ),
      DeferredActionRow,
      PrefetchHooks Function()
    >;
typedef $$TransferJobsTableCreateCompanionBuilder =
    TransferJobsCompanion Function({
      Value<int> id,
      required String kind,
      Value<int?> attachmentRowid,
      Value<String?> mediaId,
      Value<String?> localPath,
      Value<int> size,
      Value<int> offset,
      Value<Uint8List?> mediaKey,
      Value<String?> purpose,
      required TransferState state,
      Value<int> attempts,
      required DateTime nextAttemptAt,
      Value<DateTime?> leaseUntil,
      Value<String?> lastError,
      required DateTime createdAt,
    });
typedef $$TransferJobsTableUpdateCompanionBuilder =
    TransferJobsCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<int?> attachmentRowid,
      Value<String?> mediaId,
      Value<String?> localPath,
      Value<int> size,
      Value<int> offset,
      Value<Uint8List?> mediaKey,
      Value<String?> purpose,
      Value<TransferState> state,
      Value<int> attempts,
      Value<DateTime> nextAttemptAt,
      Value<DateTime?> leaseUntil,
      Value<String?> lastError,
      Value<DateTime> createdAt,
    });

final class $$TransferJobsTableReferences
    extends BaseReferences<_$HelixDb, $TransferJobsTable, TransferRow> {
  $$TransferJobsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AttachmentsTable _attachmentRowidTable(_$HelixDb db) => db.attachments
      .createAlias('transfer_jobs__attachment_rowid__attachments__id');

  $$AttachmentsTableProcessedTableManager? get attachmentRowid {
    final $_column = $_itemColumn<int>('attachment_rowid');
    if ($_column == null) return null;
    final manager = $$AttachmentsTableTableManager(
      $_db,
      $_db.attachments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_attachmentRowidTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TransferJobsTableFilterComposer
    extends Composer<_$HelixDb, $TransferJobsTable> {
  $$TransferJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get offset => $composableBuilder(
    column: $table.offset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TransferState, TransferState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get nextAttemptAt =>
      $composableBuilder(
        column: $table.nextAttemptAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get leaseUntil =>
      $composableBuilder(
        column: $table.leaseUntil,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$AttachmentsTableFilterComposer get attachmentRowid {
    final $$AttachmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.attachmentRowid,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentsTableFilterComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransferJobsTableOrderingComposer
    extends Composer<_$HelixDb, $TransferJobsTable> {
  $$TransferJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offset => $composableBuilder(
    column: $table.offset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get leaseUntil => $composableBuilder(
    column: $table.leaseUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AttachmentsTableOrderingComposer get attachmentRowid {
    final $$AttachmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.attachmentRowid,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentsTableOrderingComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransferJobsTableAnnotationComposer
    extends Composer<_$HelixDb, $TransferJobsTable> {
  $$TransferJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<int> get offset =>
      $composableBuilder(column: $table.offset, builder: (column) => column);

  GeneratedColumn<Uint8List> get mediaKey =>
      $composableBuilder(column: $table.mediaKey, builder: (column) => column);

  GeneratedColumn<String> get purpose =>
      $composableBuilder(column: $table.purpose, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TransferState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get nextAttemptAt =>
      $composableBuilder(
        column: $table.nextAttemptAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get leaseUntil =>
      $composableBuilder(
        column: $table.leaseUntil,
        builder: (column) => column,
      );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$AttachmentsTableAnnotationComposer get attachmentRowid {
    final $$AttachmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.attachmentRowid,
      referencedTable: $db.attachments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.attachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransferJobsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $TransferJobsTable,
          TransferRow,
          $$TransferJobsTableFilterComposer,
          $$TransferJobsTableOrderingComposer,
          $$TransferJobsTableAnnotationComposer,
          $$TransferJobsTableCreateCompanionBuilder,
          $$TransferJobsTableUpdateCompanionBuilder,
          (TransferRow, $$TransferJobsTableReferences),
          TransferRow,
          PrefetchHooks Function({bool attachmentRowid})
        > {
  $$TransferJobsTableTableManager(_$HelixDb db, $TransferJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransferJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransferJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransferJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int?> attachmentRowid = const Value.absent(),
                Value<String?> mediaId = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> offset = const Value.absent(),
                Value<Uint8List?> mediaKey = const Value.absent(),
                Value<String?> purpose = const Value.absent(),
                Value<TransferState> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> nextAttemptAt = const Value.absent(),
                Value<DateTime?> leaseUntil = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TransferJobsCompanion(
                id: id,
                kind: kind,
                attachmentRowid: attachmentRowid,
                mediaId: mediaId,
                localPath: localPath,
                size: size,
                offset: offset,
                mediaKey: mediaKey,
                purpose: purpose,
                state: state,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                leaseUntil: leaseUntil,
                lastError: lastError,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                Value<int?> attachmentRowid = const Value.absent(),
                Value<String?> mediaId = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> offset = const Value.absent(),
                Value<Uint8List?> mediaKey = const Value.absent(),
                Value<String?> purpose = const Value.absent(),
                required TransferState state,
                Value<int> attempts = const Value.absent(),
                required DateTime nextAttemptAt,
                Value<DateTime?> leaseUntil = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
              }) => TransferJobsCompanion.insert(
                id: id,
                kind: kind,
                attachmentRowid: attachmentRowid,
                mediaId: mediaId,
                localPath: localPath,
                size: size,
                offset: offset,
                mediaKey: mediaKey,
                purpose: purpose,
                state: state,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                leaseUntil: leaseUntil,
                lastError: lastError,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TransferJobsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({attachmentRowid = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (attachmentRowid) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.attachmentRowid,
                                referencedTable: $$TransferJobsTableReferences
                                    ._attachmentRowidTable(db),
                                referencedColumn: $$TransferJobsTableReferences
                                    ._attachmentRowidTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TransferJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $TransferJobsTable,
      TransferRow,
      $$TransferJobsTableFilterComposer,
      $$TransferJobsTableOrderingComposer,
      $$TransferJobsTableAnnotationComposer,
      $$TransferJobsTableCreateCompanionBuilder,
      $$TransferJobsTableUpdateCompanionBuilder,
      (TransferRow, $$TransferJobsTableReferences),
      TransferRow,
      PrefetchHooks Function({bool attachmentRowid})
    >;
typedef $$TransferChunksTableCreateCompanionBuilder =
    TransferChunksCompanion Function({
      required String transferId,
      required int sequence,
      required Uint8List payload,
      required int total,
      Value<bool> isFinal,
      required DateTime receivedAt,
      Value<int> rowid,
    });
typedef $$TransferChunksTableUpdateCompanionBuilder =
    TransferChunksCompanion Function({
      Value<String> transferId,
      Value<int> sequence,
      Value<Uint8List> payload,
      Value<int> total,
      Value<bool> isFinal,
      Value<DateTime> receivedAt,
      Value<int> rowid,
    });

class $$TransferChunksTableFilterComposer
    extends Composer<_$HelixDb, $TransferChunksTable> {
  $$TransferChunksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFinal => $composableBuilder(
    column: $table.isFinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get receivedAt =>
      $composableBuilder(
        column: $table.receivedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$TransferChunksTableOrderingComposer
    extends Composer<_$HelixDb, $TransferChunksTable> {
  $$TransferChunksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFinal => $composableBuilder(
    column: $table.isFinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransferChunksTableAnnotationComposer
    extends Composer<_$HelixDb, $TransferChunksTable> {
  $$TransferChunksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<bool> get isFinal =>
      $composableBuilder(column: $table.isFinal, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get receivedAt =>
      $composableBuilder(
        column: $table.receivedAt,
        builder: (column) => column,
      );
}

class $$TransferChunksTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $TransferChunksTable,
          TransferChunkRow,
          $$TransferChunksTableFilterComposer,
          $$TransferChunksTableOrderingComposer,
          $$TransferChunksTableAnnotationComposer,
          $$TransferChunksTableCreateCompanionBuilder,
          $$TransferChunksTableUpdateCompanionBuilder,
          (
            TransferChunkRow,
            BaseReferences<_$HelixDb, $TransferChunksTable, TransferChunkRow>,
          ),
          TransferChunkRow,
          PrefetchHooks Function()
        > {
  $$TransferChunksTableTableManager(_$HelixDb db, $TransferChunksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransferChunksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransferChunksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransferChunksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> transferId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<int> total = const Value.absent(),
                Value<bool> isFinal = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransferChunksCompanion(
                transferId: transferId,
                sequence: sequence,
                payload: payload,
                total: total,
                isFinal: isFinal,
                receivedAt: receivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String transferId,
                required int sequence,
                required Uint8List payload,
                required int total,
                Value<bool> isFinal = const Value.absent(),
                required DateTime receivedAt,
                Value<int> rowid = const Value.absent(),
              }) => TransferChunksCompanion.insert(
                transferId: transferId,
                sequence: sequence,
                payload: payload,
                total: total,
                isFinal: isFinal,
                receivedAt: receivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransferChunksTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $TransferChunksTable,
      TransferChunkRow,
      $$TransferChunksTableFilterComposer,
      $$TransferChunksTableOrderingComposer,
      $$TransferChunksTableAnnotationComposer,
      $$TransferChunksTableCreateCompanionBuilder,
      $$TransferChunksTableUpdateCompanionBuilder,
      (
        TransferChunkRow,
        BaseReferences<_$HelixDb, $TransferChunksTable, TransferChunkRow>,
      ),
      TransferChunkRow,
      PrefetchHooks Function()
    >;
typedef $$GroupsTableCreateCompanionBuilder =
    GroupsCompanion Function({
      required String id,
      required String title,
      Value<Uint8List?> avatar,
      required String role,
      Value<int> epoch,
      Value<Uint8List?> state,
      Value<int> stateVersion,
      Value<bool> archived,
      Value<bool> muted,
      Value<int?> lastMessageRowid,
      Value<String?> lastMessageSortKey,
      Value<DateTime?> lastMessageAt,
      Value<String?> lastMessagePreview,
      Value<int> unreadCount,
      Value<int> mentionCount,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$GroupsTableUpdateCompanionBuilder =
    GroupsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<Uint8List?> avatar,
      Value<String> role,
      Value<int> epoch,
      Value<Uint8List?> state,
      Value<int> stateVersion,
      Value<bool> archived,
      Value<bool> muted,
      Value<int?> lastMessageRowid,
      Value<String?> lastMessageSortKey,
      Value<DateTime?> lastMessageAt,
      Value<String?> lastMessagePreview,
      Value<int> unreadCount,
      Value<int> mentionCount,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$GroupsTableReferences
    extends BaseReferences<_$HelixDb, $GroupsTable, GroupRow> {
  $$GroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GroupMembersTable, List<GroupMemberRow>>
  _groupMembersRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.groupMembers,
    aliasName: 'groups__id__group_members__group_id',
  );

  $$GroupMembersTableProcessedTableManager get groupMembersRefs {
    final manager = $$GroupMembersTableTableManager(
      $_db,
      $_db.groupMembers,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_groupMembersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$GroupBansTable, List<GroupBanRow>>
  _groupBansRefsTable(_$HelixDb db) => MultiTypedResultKey.fromTable(
    db.groupBans,
    aliasName: 'groups__id__group_bans__group_id',
  );

  $$GroupBansTableProcessedTableManager get groupBansRefs {
    final manager = $$GroupBansTableTableManager(
      $_db,
      $_db.groupBans,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_groupBansRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GroupsTableFilterComposer extends Composer<_$HelixDb, $GroupsTable> {
  $$GroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get muted => $composableBuilder(
    column: $table.muted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastMessageRowid => $composableBuilder(
    column: $table.lastMessageRowid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageSortKey => $composableBuilder(
    column: $table.lastMessageSortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get lastMessageAt =>
      $composableBuilder(
        column: $table.lastMessageAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mentionCount => $composableBuilder(
    column: $table.mentionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  Expression<bool> groupMembersRefs(
    Expression<bool> Function($$GroupMembersTableFilterComposer f) f,
  ) {
    final $$GroupMembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.groupMembers,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupMembersTableFilterComposer(
            $db: $db,
            $table: $db.groupMembers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> groupBansRefs(
    Expression<bool> Function($$GroupBansTableFilterComposer f) f,
  ) {
    final $$GroupBansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.groupBans,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupBansTableFilterComposer(
            $db: $db,
            $table: $db.groupBans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GroupsTableOrderingComposer extends Composer<_$HelixDb, $GroupsTable> {
  $$GroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get muted => $composableBuilder(
    column: $table.muted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageRowid => $composableBuilder(
    column: $table.lastMessageRowid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageSortKey => $composableBuilder(
    column: $table.lastMessageSortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mentionCount => $composableBuilder(
    column: $table.mentionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupsTableAnnotationComposer
    extends Composer<_$HelixDb, $GroupsTable> {
  $$GroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<Uint8List> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);

  GeneratedColumn<Uint8List> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get stateVersion => $composableBuilder(
    column: $table.stateVersion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<bool> get muted =>
      $composableBuilder(column: $table.muted, builder: (column) => column);

  GeneratedColumn<int> get lastMessageRowid => $composableBuilder(
    column: $table.lastMessageRowid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageSortKey => $composableBuilder(
    column: $table.lastMessageSortKey,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastMessageAt =>
      $composableBuilder(
        column: $table.lastMessageAt,
        builder: (column) => column,
      );

  GeneratedColumn<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mentionCount => $composableBuilder(
    column: $table.mentionCount,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> groupMembersRefs<T extends Object>(
    Expression<T> Function($$GroupMembersTableAnnotationComposer a) f,
  ) {
    final $$GroupMembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.groupMembers,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupMembersTableAnnotationComposer(
            $db: $db,
            $table: $db.groupMembers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> groupBansRefs<T extends Object>(
    Expression<T> Function($$GroupBansTableAnnotationComposer a) f,
  ) {
    final $$GroupBansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.groupBans,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupBansTableAnnotationComposer(
            $db: $db,
            $table: $db.groupBans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GroupsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $GroupsTable,
          GroupRow,
          $$GroupsTableFilterComposer,
          $$GroupsTableOrderingComposer,
          $$GroupsTableAnnotationComposer,
          $$GroupsTableCreateCompanionBuilder,
          $$GroupsTableUpdateCompanionBuilder,
          (GroupRow, $$GroupsTableReferences),
          GroupRow,
          PrefetchHooks Function({bool groupMembersRefs, bool groupBansRefs})
        > {
  $$GroupsTableTableManager(_$HelixDb db, $GroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<Uint8List?> avatar = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<int> epoch = const Value.absent(),
                Value<Uint8List?> state = const Value.absent(),
                Value<int> stateVersion = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> muted = const Value.absent(),
                Value<int?> lastMessageRowid = const Value.absent(),
                Value<String?> lastMessageSortKey = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> mentionCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupsCompanion(
                id: id,
                title: title,
                avatar: avatar,
                role: role,
                epoch: epoch,
                state: state,
                stateVersion: stateVersion,
                archived: archived,
                muted: muted,
                lastMessageRowid: lastMessageRowid,
                lastMessageSortKey: lastMessageSortKey,
                lastMessageAt: lastMessageAt,
                lastMessagePreview: lastMessagePreview,
                unreadCount: unreadCount,
                mentionCount: mentionCount,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<Uint8List?> avatar = const Value.absent(),
                required String role,
                Value<int> epoch = const Value.absent(),
                Value<Uint8List?> state = const Value.absent(),
                Value<int> stateVersion = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> muted = const Value.absent(),
                Value<int?> lastMessageRowid = const Value.absent(),
                Value<String?> lastMessageSortKey = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> mentionCount = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => GroupsCompanion.insert(
                id: id,
                title: title,
                avatar: avatar,
                role: role,
                epoch: epoch,
                state: state,
                stateVersion: stateVersion,
                archived: archived,
                muted: muted,
                lastMessageRowid: lastMessageRowid,
                lastMessageSortKey: lastMessageSortKey,
                lastMessageAt: lastMessageAt,
                lastMessagePreview: lastMessagePreview,
                unreadCount: unreadCount,
                mentionCount: mentionCount,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$GroupsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({groupMembersRefs = false, groupBansRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (groupMembersRefs) db.groupMembers,
                    if (groupBansRefs) db.groupBans,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (groupMembersRefs)
                        await $_getPrefetchedData<
                          GroupRow,
                          $GroupsTable,
                          GroupMemberRow
                        >(
                          currentTable: table,
                          referencedTable: $$GroupsTableReferences
                              ._groupMembersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GroupsTableReferences(
                                db,
                                table,
                                p0,
                              ).groupMembersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.groupId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (groupBansRefs)
                        await $_getPrefetchedData<
                          GroupRow,
                          $GroupsTable,
                          GroupBanRow
                        >(
                          currentTable: table,
                          referencedTable: $$GroupsTableReferences
                              ._groupBansRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GroupsTableReferences(
                                db,
                                table,
                                p0,
                              ).groupBansRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.groupId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$GroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $GroupsTable,
      GroupRow,
      $$GroupsTableFilterComposer,
      $$GroupsTableOrderingComposer,
      $$GroupsTableAnnotationComposer,
      $$GroupsTableCreateCompanionBuilder,
      $$GroupsTableUpdateCompanionBuilder,
      (GroupRow, $$GroupsTableReferences),
      GroupRow,
      PrefetchHooks Function({bool groupMembersRefs, bool groupBansRefs})
    >;
typedef $$GroupMembersTableCreateCompanionBuilder =
    GroupMembersCompanion Function({
      required String groupId,
      required String accountId,
      required String qualifiedId,
      Value<String?> displayName,
      required String role,
      Value<bool> isSelf,
      required String devicesJson,
      Value<DateTime?> devicesFetchedAt,
      Value<DateTime?> joinedAt,
      Value<int> rowid,
    });
typedef $$GroupMembersTableUpdateCompanionBuilder =
    GroupMembersCompanion Function({
      Value<String> groupId,
      Value<String> accountId,
      Value<String> qualifiedId,
      Value<String?> displayName,
      Value<String> role,
      Value<bool> isSelf,
      Value<String> devicesJson,
      Value<DateTime?> devicesFetchedAt,
      Value<DateTime?> joinedAt,
      Value<int> rowid,
    });

final class $$GroupMembersTableReferences
    extends BaseReferences<_$HelixDb, $GroupMembersTable, GroupMemberRow> {
  $$GroupMembersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GroupsTable _groupIdTable(_$HelixDb db) =>
      db.groups.createAlias('group_members__group_id__groups__id');

  $$GroupsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<String>('group_id')!;

    final manager = $$GroupsTableTableManager(
      $_db,
      $_db.groups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GroupMembersTableFilterComposer
    extends Composer<_$HelixDb, $GroupMembersTable> {
  $$GroupMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get qualifiedId => $composableBuilder(
    column: $table.qualifiedId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSelf => $composableBuilder(
    column: $table.isSelf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get devicesJson => $composableBuilder(
    column: $table.devicesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int>
  get devicesFetchedAt => $composableBuilder(
    column: $table.devicesFetchedAt,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get joinedAt =>
      $composableBuilder(
        column: $table.joinedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$GroupsTableFilterComposer get groupId {
    final $$GroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableFilterComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableOrderingComposer
    extends Composer<_$HelixDb, $GroupMembersTable> {
  $$GroupMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qualifiedId => $composableBuilder(
    column: $table.qualifiedId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSelf => $composableBuilder(
    column: $table.isSelf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get devicesJson => $composableBuilder(
    column: $table.devicesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get devicesFetchedAt => $composableBuilder(
    column: $table.devicesFetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedAt => $composableBuilder(
    column: $table.joinedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$GroupsTableOrderingComposer get groupId {
    final $$GroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableOrderingComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableAnnotationComposer
    extends Composer<_$HelixDb, $GroupMembersTable> {
  $$GroupMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get qualifiedId => $composableBuilder(
    column: $table.qualifiedId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<bool> get isSelf =>
      $composableBuilder(column: $table.isSelf, builder: (column) => column);

  GeneratedColumn<String> get devicesJson => $composableBuilder(
    column: $table.devicesJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get devicesFetchedAt =>
      $composableBuilder(
        column: $table.devicesFetchedAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get joinedAt =>
      $composableBuilder(column: $table.joinedAt, builder: (column) => column);

  $$GroupsTableAnnotationComposer get groupId {
    final $$GroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $GroupMembersTable,
          GroupMemberRow,
          $$GroupMembersTableFilterComposer,
          $$GroupMembersTableOrderingComposer,
          $$GroupMembersTableAnnotationComposer,
          $$GroupMembersTableCreateCompanionBuilder,
          $$GroupMembersTableUpdateCompanionBuilder,
          (GroupMemberRow, $$GroupMembersTableReferences),
          GroupMemberRow,
          PrefetchHooks Function({bool groupId})
        > {
  $$GroupMembersTableTableManager(_$HelixDb db, $GroupMembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> qualifiedId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<bool> isSelf = const Value.absent(),
                Value<String> devicesJson = const Value.absent(),
                Value<DateTime?> devicesFetchedAt = const Value.absent(),
                Value<DateTime?> joinedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupMembersCompanion(
                groupId: groupId,
                accountId: accountId,
                qualifiedId: qualifiedId,
                displayName: displayName,
                role: role,
                isSelf: isSelf,
                devicesJson: devicesJson,
                devicesFetchedAt: devicesFetchedAt,
                joinedAt: joinedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String accountId,
                required String qualifiedId,
                Value<String?> displayName = const Value.absent(),
                required String role,
                Value<bool> isSelf = const Value.absent(),
                required String devicesJson,
                Value<DateTime?> devicesFetchedAt = const Value.absent(),
                Value<DateTime?> joinedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupMembersCompanion.insert(
                groupId: groupId,
                accountId: accountId,
                qualifiedId: qualifiedId,
                displayName: displayName,
                role: role,
                isSelf: isSelf,
                devicesJson: devicesJson,
                devicesFetchedAt: devicesFetchedAt,
                joinedAt: joinedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GroupMembersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.groupId,
                                referencedTable: $$GroupMembersTableReferences
                                    ._groupIdTable(db),
                                referencedColumn: $$GroupMembersTableReferences
                                    ._groupIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GroupMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $GroupMembersTable,
      GroupMemberRow,
      $$GroupMembersTableFilterComposer,
      $$GroupMembersTableOrderingComposer,
      $$GroupMembersTableAnnotationComposer,
      $$GroupMembersTableCreateCompanionBuilder,
      $$GroupMembersTableUpdateCompanionBuilder,
      (GroupMemberRow, $$GroupMembersTableReferences),
      GroupMemberRow,
      PrefetchHooks Function({bool groupId})
    >;
typedef $$GroupBansTableCreateCompanionBuilder =
    GroupBansCompanion Function({
      required String groupId,
      required String accountId,
      required DateTime bannedAt,
      Value<int> rowid,
    });
typedef $$GroupBansTableUpdateCompanionBuilder =
    GroupBansCompanion Function({
      Value<String> groupId,
      Value<String> accountId,
      Value<DateTime> bannedAt,
      Value<int> rowid,
    });

final class $$GroupBansTableReferences
    extends BaseReferences<_$HelixDb, $GroupBansTable, GroupBanRow> {
  $$GroupBansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GroupsTable _groupIdTable(_$HelixDb db) =>
      db.groups.createAlias('group_bans__group_id__groups__id');

  $$GroupsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<String>('group_id')!;

    final manager = $$GroupsTableTableManager(
      $_db,
      $_db.groups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GroupBansTableFilterComposer
    extends Composer<_$HelixDb, $GroupBansTable> {
  $$GroupBansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get bannedAt =>
      $composableBuilder(
        column: $table.bannedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$GroupsTableFilterComposer get groupId {
    final $$GroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableFilterComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupBansTableOrderingComposer
    extends Composer<_$HelixDb, $GroupBansTable> {
  $$GroupBansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bannedAt => $composableBuilder(
    column: $table.bannedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$GroupsTableOrderingComposer get groupId {
    final $$GroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableOrderingComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupBansTableAnnotationComposer
    extends Composer<_$HelixDb, $GroupBansTable> {
  $$GroupBansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get bannedAt =>
      $composableBuilder(column: $table.bannedAt, builder: (column) => column);

  $$GroupsTableAnnotationComposer get groupId {
    final $$GroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.groups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupBansTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $GroupBansTable,
          GroupBanRow,
          $$GroupBansTableFilterComposer,
          $$GroupBansTableOrderingComposer,
          $$GroupBansTableAnnotationComposer,
          $$GroupBansTableCreateCompanionBuilder,
          $$GroupBansTableUpdateCompanionBuilder,
          (GroupBanRow, $$GroupBansTableReferences),
          GroupBanRow,
          PrefetchHooks Function({bool groupId})
        > {
  $$GroupBansTableTableManager(_$HelixDb db, $GroupBansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupBansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupBansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupBansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<DateTime> bannedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupBansCompanion(
                groupId: groupId,
                accountId: accountId,
                bannedAt: bannedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String accountId,
                required DateTime bannedAt,
                Value<int> rowid = const Value.absent(),
              }) => GroupBansCompanion.insert(
                groupId: groupId,
                accountId: accountId,
                bannedAt: bannedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GroupBansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.groupId,
                                referencedTable: $$GroupBansTableReferences
                                    ._groupIdTable(db),
                                referencedColumn: $$GroupBansTableReferences
                                    ._groupIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GroupBansTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $GroupBansTable,
      GroupBanRow,
      $$GroupBansTableFilterComposer,
      $$GroupBansTableOrderingComposer,
      $$GroupBansTableAnnotationComposer,
      $$GroupBansTableCreateCompanionBuilder,
      $$GroupBansTableUpdateCompanionBuilder,
      (GroupBanRow, $$GroupBansTableReferences),
      GroupBanRow,
      PrefetchHooks Function({bool groupId})
    >;
typedef $$CallLogTableCreateCompanionBuilder =
    CallLogCompanion Function({
      required String callId,
      required String peerAccountId,
      Value<String?> peerDisplayName,
      required String kind,
      required String direction,
      Value<bool> video,
      required String state,
      required DateTime startedAt,
      Value<DateTime?> answeredAt,
      Value<DateTime?> endedAt,
      Value<int> rowid,
    });
typedef $$CallLogTableUpdateCompanionBuilder =
    CallLogCompanion Function({
      Value<String> callId,
      Value<String> peerAccountId,
      Value<String?> peerDisplayName,
      Value<String> kind,
      Value<String> direction,
      Value<bool> video,
      Value<String> state,
      Value<DateTime> startedAt,
      Value<DateTime?> answeredAt,
      Value<DateTime?> endedAt,
      Value<int> rowid,
    });

class $$CallLogTableFilterComposer extends Composer<_$HelixDb, $CallLogTable> {
  $$CallLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get callId => $composableBuilder(
    column: $table.callId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerAccountId => $composableBuilder(
    column: $table.peerAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get video => $composableBuilder(
    column: $table.video,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get startedAt =>
      $composableBuilder(
        column: $table.startedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get answeredAt =>
      $composableBuilder(
        column: $table.answeredAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get endedAt =>
      $composableBuilder(
        column: $table.endedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$CallLogTableOrderingComposer
    extends Composer<_$HelixDb, $CallLogTable> {
  $$CallLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get callId => $composableBuilder(
    column: $table.callId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerAccountId => $composableBuilder(
    column: $table.peerAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get video => $composableBuilder(
    column: $table.video,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get answeredAt => $composableBuilder(
    column: $table.answeredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CallLogTableAnnotationComposer
    extends Composer<_$HelixDb, $CallLogTable> {
  $$CallLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get callId =>
      $composableBuilder(column: $table.callId, builder: (column) => column);

  GeneratedColumn<String> get peerAccountId => $composableBuilder(
    column: $table.peerAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerDisplayName => $composableBuilder(
    column: $table.peerDisplayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<bool> get video =>
      $composableBuilder(column: $table.video, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get answeredAt =>
      $composableBuilder(
        column: $table.answeredAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);
}

class $$CallLogTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $CallLogTable,
          CallLogRow,
          $$CallLogTableFilterComposer,
          $$CallLogTableOrderingComposer,
          $$CallLogTableAnnotationComposer,
          $$CallLogTableCreateCompanionBuilder,
          $$CallLogTableUpdateCompanionBuilder,
          (CallLogRow, BaseReferences<_$HelixDb, $CallLogTable, CallLogRow>),
          CallLogRow,
          PrefetchHooks Function()
        > {
  $$CallLogTableTableManager(_$HelixDb db, $CallLogTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CallLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CallLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CallLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> callId = const Value.absent(),
                Value<String> peerAccountId = const Value.absent(),
                Value<String?> peerDisplayName = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<bool> video = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> answeredAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CallLogCompanion(
                callId: callId,
                peerAccountId: peerAccountId,
                peerDisplayName: peerDisplayName,
                kind: kind,
                direction: direction,
                video: video,
                state: state,
                startedAt: startedAt,
                answeredAt: answeredAt,
                endedAt: endedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String callId,
                required String peerAccountId,
                Value<String?> peerDisplayName = const Value.absent(),
                required String kind,
                required String direction,
                Value<bool> video = const Value.absent(),
                required String state,
                required DateTime startedAt,
                Value<DateTime?> answeredAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CallLogCompanion.insert(
                callId: callId,
                peerAccountId: peerAccountId,
                peerDisplayName: peerDisplayName,
                kind: kind,
                direction: direction,
                video: video,
                state: state,
                startedAt: startedAt,
                answeredAt: answeredAt,
                endedAt: endedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CallLogTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $CallLogTable,
      CallLogRow,
      $$CallLogTableFilterComposer,
      $$CallLogTableOrderingComposer,
      $$CallLogTableAnnotationComposer,
      $$CallLogTableCreateCompanionBuilder,
      $$CallLogTableUpdateCompanionBuilder,
      (CallLogRow, BaseReferences<_$HelixDb, $CallLogTable, CallLogRow>),
      CallLogRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$HelixDb, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$HelixDb, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$HelixDb, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$HelixDb,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (SettingRow, BaseReferences<_$HelixDb, $SettingsTable, SettingRow>),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$HelixDb db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$HelixDb,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$HelixDb, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $HelixDbManager {
  final _$HelixDb _db;
  $HelixDbManager(this._db);
  $MessagesFtsTableManager get messagesFts =>
      $MessagesFtsTableManager(_db, _db.messagesFts);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$MessageReactionsTableTableManager get messageReactions =>
      $$MessageReactionsTableTableManager(_db, _db.messageReactions);
  $$MessageReceiptsTableTableManager get messageReceipts =>
      $$MessageReceiptsTableTableManager(_db, _db.messageReceipts);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
  $$ConversationMembersTableTableManager get conversationMembers =>
      $$ConversationMembersTableTableManager(_db, _db.conversationMembers);
  $$SelfAccountTableTableManager get selfAccount =>
      $$SelfAccountTableTableManager(_db, _db.selfAccount);
  $$SelfDevicesTableTableManager get selfDevices =>
      $$SelfDevicesTableTableManager(_db, _db.selfDevices);
  $$PeopleTableTableManager get people =>
      $$PeopleTableTableManager(_db, _db.people);
  $$PersonDevicesTableTableManager get personDevices =>
      $$PersonDevicesTableTableManager(_db, _db.personDevices);
  $$IdentityTableTableManager get identity =>
      $$IdentityTableTableManager(_db, _db.identity);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$PrekeysTableTableManager get prekeys =>
      $$PrekeysTableTableManager(_db, _db.prekeys);
  $$SenderKeysTableTableManager get senderKeys =>
      $$SenderKeysTableTableManager(_db, _db.senderKeys);
  $$InboxCursorTableTableManager get inboxCursor =>
      $$InboxCursorTableTableManager(_db, _db.inboxCursor);
  $$ProcessedEnvelopesTableTableManager get processedEnvelopes =>
      $$ProcessedEnvelopesTableTableManager(_db, _db.processedEnvelopes);
  $$OutboxOpsTableTableManager get outboxOps =>
      $$OutboxOpsTableTableManager(_db, _db.outboxOps);
  $$DeferredActionsTableTableManager get deferredActions =>
      $$DeferredActionsTableTableManager(_db, _db.deferredActions);
  $$TransferJobsTableTableManager get transferJobs =>
      $$TransferJobsTableTableManager(_db, _db.transferJobs);
  $$TransferChunksTableTableManager get transferChunks =>
      $$TransferChunksTableTableManager(_db, _db.transferChunks);
  $$GroupsTableTableManager get groups =>
      $$GroupsTableTableManager(_db, _db.groups);
  $$GroupMembersTableTableManager get groupMembers =>
      $$GroupMembersTableTableManager(_db, _db.groupMembers);
  $$GroupBansTableTableManager get groupBans =>
      $$GroupBansTableTableManager(_db, _db.groupBans);
  $$CallLogTableTableManager get callLog =>
      $$CallLogTableTableManager(_db, _db.callLog);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
