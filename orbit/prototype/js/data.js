/*
  Sample data, shaped like the Flutter view models so screens read the same
  fields the real app will hand them. Nothing here talks to a server.
*/
const Data = (() => {
  const me = { id: 'me', name: 'Hasan', about: 'Building Orbit', helixName: 'hasan', number: '+880 1711-000001', masked: '+880 17•• ••0001', server: 'Orbit Global', host: 'helix.agiletechbd.com' };

  const p = (id, names, extra = {}) => ({ id, names, ...extra });
  const people = {
    nadia: p('nadia', { phoneBookName: 'Nadia Rahman', number: '+880 1712-458921', helixName: 'nadia.r' }, { about: 'Somewhere between deadlines', online: true, verified: true }),
    arif: p('arif', { phoneBookName: 'Arif Hossain', number: '+880 1819-220341', helixName: 'arif' }, { about: 'Available' }),
    ammu: p('ammu', { phoneBookName: 'Ammu', number: '+880 1711-302118' }, {}),
    abbu: p('abbu', { phoneBookName: 'Abbu', number: '+880 1711-302119' }, {}),
    tanvir: p('tanvir', { phoneBookName: 'Tanvir Ahmed', number: '+880 1913-774520', helixName: 'tanvir.a' }, { about: 'Product at Aurko' }),
    sadia: p('sadia', { phoneBookName: 'Sadia Islam', number: '+880 1715-660012', helixName: 'sadia' }, { about: 'Design is how it works' }),
    rafiq: p('rafiq', { nickname: 'Rafiq Bhai', number: '+880 1612-118844' }, {}),
    unknown: p('unknown', { number: '+880 1812-345678' }, {}),
    mehjabin: p('mehjabin', { helixName: 'mehjabin' }, {}),
    rumana: p('rumana', { phoneBookName: 'Rumana Apu', number: '+880 1755-901234' }, {}),
    shuvo: p('shuvo', { phoneBookName: 'Shuvo', number: '+880 1977-412300', helixName: 'shuvo' }, { blocked: true }),
    karim: p('karim', { phoneBookName: 'Karim Uncle', number: '+880 1711-555013' }, {}),
  };

  /** HelixPersonNames.display */
  function displayName(person) {
    const n = person.names;
    return n.phoneBookName || n.nickname || n.number || (n.helixName ? `~${n.helixName}` : 'Orbit user');
  }
  /** HelixPersonNames.secondary */
  function secondary(person) {
    const n = person.names;
    if (n.phoneBookName || n.nickname) return n.number || (n.helixName ? `~${n.helixName}` : null);
    if (n.number) return n.helixName ? `~${n.helixName}` : null;
    return null;
  }
  const av = (person) => ({ name: displayName(person), seed: person.id });

  // ---------------------------------------------------- chat list rows
  const chats = [
    { id: 'direct:nadia', title: 'Nadia Rahman', avatar: av(people.nadia), preview: { text: 'Sent the photos from Cox’s Bazar 🌊', kind: 'text' }, timeLabel: '09:41', unreadCount: 2, pinned: true, verified: true },
    { id: 'group:family', title: 'Family', avatar: { name: 'Family', seed: 'family', group: true }, preview: { text: 'Dinner at 8, don’t be late @Hasan', kind: 'text', senderPrefix: 'Ammu' }, timeLabel: '09:12', unreadCount: 5, hasMention: true, pinned: true },
    { id: 'direct:arif', title: 'Arif Hossain', avatar: av(people.arif), preview: { text: 'See you at 6 then', kind: 'text', status: 'read', senderPrefix: 'You' }, timeLabel: '08:30' },
    { id: 'group:studio', title: 'Studio North', avatar: { name: 'Studio North', seed: 'studio', group: true }, typingLabel: 'Sadia and Tanvir are typing...', preview: { text: 'Final assets are in the drive', kind: 'text', senderPrefix: 'Sadia' }, timeLabel: '08:15', unreadCount: 3 },
    { id: 'group:design', title: 'Design Team', avatar: { name: 'Design Team', seed: 'design', group: true }, preview: { text: '', kind: 'image', senderPrefix: 'Sadia' }, timeLabel: '08:02', unreadCount: 12, muted: true },
    { id: 'direct:tanvir', title: 'Tanvir Ahmed', avatar: av(people.tanvir), preview: { text: 'I’ll send the doc tonight', kind: 'text', isDraft: true }, timeLabel: 'Yesterday' },
    { id: 'direct:unknown', title: '+880 1812-345678', avatar: av(people.unknown), preview: { text: '', kind: 'voiceNote' }, timeLabel: 'Yesterday', unreadCount: 1 },
    { id: 'direct:rafiq', title: 'Rafiq Bhai', avatar: av(people.rafiq), preview: { text: 'Call me when you’re free', kind: 'text', status: 'failed', senderPrefix: 'You' }, timeLabel: 'Tue' },
    { id: 'group:lunch', title: 'Office Lunch', avatar: { name: 'Office Lunch', seed: 'lunch', group: true }, preview: { text: 'Star Kabab', kind: 'location', senderPrefix: 'You', status: 'delivered' }, timeLabel: 'Mon' },
    { id: 'direct:mehjabin', title: '~mehjabin', avatar: av(people.mehjabin), preview: { text: '', kind: 'deleted' }, timeLabel: 'Sun' },
    { id: 'direct:rumana', title: 'Rumana Apu', avatar: av(people.rumana), preview: { text: 'Missed voice call', kind: 'call' }, timeLabel: '12/10/26' },
    { id: 'direct:karim', title: 'Karim Uncle', avatar: av(people.karim), preview: { text: 'Eid Mubarak to all of you', kind: 'text' }, timeLabel: '08/10/26', muted: true },
  ];

  const archived = [
    { id: 'group:batch', title: 'Batch ’18', avatar: { name: 'Batch 18', seed: 'batch', group: true }, preview: { text: 'Reunion photos are up', kind: 'text', senderPrefix: 'Mahin' }, timeLabel: 'Sep 30', unreadCount: 3, archived: true, muted: true },
    { id: 'direct:shop', title: 'Gadget Shop', avatar: { name: 'Gadget Shop', seed: 'shop' }, preview: { text: 'Your order is ready for pickup', kind: 'text' }, timeLabel: 'Sep 21', archived: true },
    { id: 'direct:shuvo', title: 'Shuvo', avatar: av(people.shuvo), preview: { text: 'ok', kind: 'text', status: 'read', senderPrefix: 'You' }, timeLabel: 'Aug 02', archived: true },
  ];

  const typing = { 'direct:arif': null };

  // ------------------------------------------------------ conversations
  const wave = [40, 90, 150, 200, 120, 80, 160, 230, 180, 100, 60, 140, 210, 170, 90, 50, 120, 190, 240, 160, 110, 70, 130, 180, 150, 90, 60, 100, 170, 220, 140, 80, 50, 90, 60, 40];
  const M = (id, outgoing, content, timeLabel, extra = {}) => ({ id, outgoing, content, timeLabel, status: 'read', ...extra });
  const T = (text, extra = {}) => ({ type: 'text', text, ...extra });

  const conversations = {
    'direct:nadia': {
      peer: 'nadia',
      items: [
        { kind: 'day', label: 'Yesterday' },
        { kind: 'msg', m: M('n1', false, T('Are you still coming to the launch on Friday?'), '21:04', { authorId: 'nadia', sentAt: 1 }) },
        { kind: 'msg', m: M('n2', true, T('Yes! Wouldn’t miss it. Should I bring the prints?'), '21:06', { authorId: 'me', sentAt: 3 }) },
        { kind: 'msg', m: M('n3', false, T('Please. And the deck from last week'), '21:07', { authorId: 'nadia', sentAt: 4, reactions: [{ emoji: '👍', count: 1, mine: true }] }) },
        { kind: 'msg', m: M('n4', true, { type: 'document', name: 'Launch deck v3.pdf', sizeLabel: '4.2 MB', typeLabel: 'PDF' }, '21:09', { authorId: 'me', sentAt: 6 }) },
        { kind: 'msg', m: M('n5', true, T('Here it is. The colour pages are 14 to 22'), '21:09', { authorId: 'me', sentAt: 6, edited: true }) },
        { kind: 'notice', text: 'Missed voice call', icon: 'phone-incoming', tone: 'calllog missed' },
        { kind: 'day', label: 'Today' },
        { kind: 'msg', m: M('n6', false, T('Good morning ☀️ We got back last night'), '09:30', { authorId: 'nadia', sentAt: 100 }) },
        { kind: 'unread', count: 2 },
        { kind: 'msg', m: M('n7', false, { type: 'media', items: [{ photo: 'ph-e', width: 4, height: 3 }, { photo: 'ph-c' }, { photo: 'ph-b', isVideo: true, durationLabel: '0:24' }, { photo: 'ph-d' }, { photo: 'ph-a' }, { photo: 'ph-f' }], caption: '' }, '09:40', { authorId: 'nadia', sentAt: 110 }) },
        { kind: 'msg', m: M('n8', false, T('Sent the photos from Cox’s Bazar 🌊'), '09:41', { authorId: 'nadia', sentAt: 111, reply: { authorName: 'You', text: 'Send me the beach photos when you’re back!', authorColorIndex: 1 } }) },
      ],
      typingNext: true,
    },
    'group:family': {
      group: 'family',
      items: [
        { kind: 'day', label: '28 September 2026' },
        { kind: 'notice', text: 'Ammu created this group' },
        { kind: 'notice', text: 'Ammu added Abbu, Rumana Apu and You' },
        { kind: 'day', label: 'Sunday' },
        { kind: 'notice', text: 'Abbu set disappearing messages to 7 days' },
        { kind: 'msg', m: M('f1', false, T('Who is coming for Eid?'), '18:20', { authorId: 'ammu', authorName: 'Ammu', authorColorIndex: 5, sentAt: 1, expiresLabel: '1w' }) },
        { kind: 'msg', m: M('f2', false, T('Count me in. Rumana is coming with the kids'), '18:31', { authorId: 'abbu', authorName: 'Abbu', authorColorIndex: 3, sentAt: 12, expiresLabel: '1w' }) },
        { kind: 'msg', m: M('f3', true, T('Me too, landing Thursday night ✈️'), '18:40', { authorId: 'me', sentAt: 21, expiresLabel: '1w', reactions: [{ emoji: '❤️', count: 3 }, { emoji: '🙏', count: 1 }] }) },
        { kind: 'msg', m: M('f4', false, { type: 'audio', durationLabel: '0:42', waveform: wave, progress: 0, speed: 1, played: false }, '18:44', { authorId: 'ammu', authorName: 'Ammu', authorColorIndex: 5, sentAt: 25, expiresLabel: '1w' }) },
        { kind: 'day', label: 'Today' },
        { kind: 'msg', m: M('f5', false, { type: 'location', label: 'Location', address: 'Star Kabab, Road 2, Dhanmondi, Dhaka' }, '08:55', { authorId: 'abbu', authorName: 'Abbu', authorColorIndex: 3, sentAt: 200, expiresLabel: '1w' }) },
        { kind: 'unread', count: 2 },
        { kind: 'msg', m: M('f6', false, T('Dinner at 8, don’t be late @Hasan', { mentions: ['Hasan'] }), '09:12', { authorId: 'ammu', authorName: 'Ammu', authorColorIndex: 5, sentAt: 217, expiresLabel: '1w' }) },
        { kind: 'msg', m: M('f7', false, T('😂😂'), '09:12', { authorId: 'ammu', authorName: 'Ammu', authorColorIndex: 5, sentAt: 217, expiresLabel: '1w' }) },
      ],
    },
    'direct:arif': {
      peer: 'arif',
      items: [
        { kind: 'day', label: 'Today' },
        { kind: 'msg', m: M('a1', false, T('Check this out https://helix.agiletechbd.com/blog/v2', { linkPreview: { title: 'Orbit v2: rebuilt from the ground up', description: 'A faster engine, encrypted backups and calls that just work.', host: 'helix.agiletechbd.com' } }), '08:12', { authorId: 'arif', sentAt: 1 }) },
        { kind: 'msg', m: M('a2', true, T('Nice write-up'), '08:20', { authorId: 'me', sentAt: 9, forwarded: false }) },
        { kind: 'msg', m: M('a3', false, { type: 'contact', name: 'Sadia Islam', detail: '+880 1715-660012', onHelix: true }, '08:22', { authorId: 'arif', sentAt: 11, forwarded: true }) },
        { kind: 'msg', m: M('a4', false, { type: 'viewOnce', isVideo: false, opened: false }, '08:25', { authorId: 'arif', sentAt: 14 }) },
        { kind: 'msg', m: M('a5', false, { type: 'placeholder', kind: 'undecryptable' }, '08:26', { authorId: 'arif', sentAt: 15 }) },
        { kind: 'msg', m: M('a5b', false, { type: 'audio', isVoiceNote: false, title: 'Rooftop session.m4a', durationLabel: '3:12', waveform: wave.slice().reverse(), progress: 0, speed: 1 }, '08:26', { authorId: 'arif', sentAt: 15 }) },
        { kind: 'msg', m: M('a5c', false, { type: 'poll', question: 'Friday lunch?', options: ['Star Kabab', 'Sultan’s Dine', 'Order in'] }, '08:27', { authorId: 'arif', sentAt: 16 }) },
        { kind: 'msg', m: M('a5d', false, { type: 'placeholder', kind: 'unsupported' }, '08:27', { authorId: 'arif', sentAt: 16 }) },
        { kind: 'msg', m: M('a6', true, { type: 'media', items: [{ photo: 'ph-c', width: 3, height: 4, transfer: 'uploading', progress: 0.62 }], caption: 'The new office!' }, '08:28', { authorId: 'me', sentAt: 17, status: 'pending' }) },
        { kind: 'msg', m: M('a7', true, { type: 'placeholder', kind: 'deleted' }, '08:29', { authorId: 'me', sentAt: 18 }) },
        { kind: 'msg', m: M('a7b', true, { type: 'viewOnce', isVideo: true, opened: false }, '08:29', { authorId: 'me', sentAt: 18 }) },
        { kind: 'msg', m: M('a8', true, T('See you at 6 then'), '08:30', { authorId: 'me', sentAt: 19, status: 'read' }) },
      ],
    },
    'direct:rafiq': {
      peer: 'rafiq',
      items: [
        { kind: 'day', label: 'Tuesday' },
        { kind: 'notice', text: 'Your safety number with Rafiq Bhai changed', icon: 'shield-warning', tone: 'warn' },
        { kind: 'msg', m: M('r1', false, { type: 'document', name: 'Flat rent agreement.docx', sizeLabel: '182 KB', typeLabel: 'DOCX', transfer: 'notDownloaded' }, '14:02', { authorId: 'rafiq', sentAt: 1 }) },
        { kind: 'msg', m: M('r2', false, { type: 'media', items: [{ photo: 'ph-d', width: 16, height: 9, transfer: 'notDownloaded', sizeLabel: '2.4 MB', isVideo: true, durationLabel: '1:12' }] }, '14:03', { authorId: 'rafiq', sentAt: 2 }) },
        { kind: 'msg', m: M('r3', true, T('Call me when you’re free'), '14:30', { authorId: 'me', sentAt: 30, status: 'failed' }) },
      ],
    },
  };

  // ------------------------------------------------------------- call log
  const calls = [
    { id: 'call1', title: 'Nadia Rahman', avatar: av(people.nadia), direction: 'outgoing', video: true, timeLabel: 'Today, 10:12', peer: 'nadia' },
    { id: 'call2', title: 'Arif Hossain', avatar: av(people.arif), direction: 'missed', timeLabel: 'Today, 07:48', count: 2, peer: 'arif' },
    { id: 'call3', title: 'Ammu', avatar: av(people.ammu), direction: 'incoming', timeLabel: 'Yesterday, 21:30', count: 3, peer: 'ammu' },
    { id: 'call4', title: 'Tanvir Ahmed', avatar: av(people.tanvir), direction: 'declined', video: true, timeLabel: 'Yesterday, 15:02', peer: 'tanvir' },
    { id: 'call5', title: 'Rumana Apu', avatar: av(people.rumana), direction: 'missed', timeLabel: 'Mon, 19:20', peer: 'rumana' },
    { id: 'call6', title: '+880 1812-345678', avatar: av(people.unknown), direction: 'failed', timeLabel: 'Sun, 11:05', peer: 'unknown' },
    { id: 'call7', title: 'Sadia Islam', avatar: av(people.sadia), direction: 'outgoing', timeLabel: '8 Oct, 18:44', peer: 'sadia' },
  ];

  return { me, people, displayName, secondary, av, chats, archived, typing, conversations, calls, wave };
})();
