//
//  DMView.swift
//  damus
//
//  Created by William Casarin on 2022-07-01.
//

import SwiftUI

struct DMView: View {
    let event: NostrEvent
    let damus_state: DamusState

    var is_ours: Bool {
        event.pubkey == damus_state.pubkey
    }
    
    var Mention: some View {
        Group {
            if let mention = first_eref_mention(ev: event, privkey: damus_state.keypair.privkey) {
                BuilderEventView(damus: damus_state, event_id: mention.ref)
            } else {
                EmptyView()
            }
        }
    }
    
    var dm_options: EventViewOptions {
        var options: EventViewOptions = [.only_text]
        
        if !self.damus_state.settings.translate_dms {
            options.insert(.no_translate)
        }
        
        return options
    }
    
    func format_timestamp(timestamp: Int64) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mm a"
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return dateFormatter.string(from: date)
    }

    var DM: some View {
        HStack {
            if is_ours {
                Spacer(minLength: UIScreen.main.bounds.width * 0.2)
            }

            let should_show_img = should_show_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)

            VStack(alignment: .trailing) {
                NoteContentView(damus_state: damus_state, event: event, show_images: should_show_img, size: .normal, options: dm_options)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.top, .leading, .trailing], 10)
                    .padding([.bottom], 25)
                    .background(VisualEffectView(effect: UIBlurEffect(style: .prominent))
                        .background(is_ours ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.15))
                    )
                    .cornerRadius(8.0)
                    .tint(is_ours ? Color.white : Color.accentColor)

                Text(format_relative_time(event.created_at))
                   .font(.footnote)
                   .foregroundColor(.gray)
                   .opacity(0.8)
            }

            if !is_ours {
                Spacer(minLength: UIScreen.main.bounds.width * 0.2)
            }
        }
    }

    func Image(urls: [MediaUrl]) -> some View {
        return Group {
            HStack {
                if is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
                
                let should_show_img = should_show_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
                if should_show_img {
                    ImageCarousel(state: damus_state, evid: event.id, urls: urls)
                        .clipShape(ChatBubbleShape(direction: isLastInGroup ? (is_ours ? ChatBubbleShape.Direction.right: ChatBubbleShape.Direction.left): ChatBubbleShape.Direction.none))
                        .contextMenu{MenuItems(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads)}
                } else if !should_show_img {
                    ZStack {
                        ImageCarousel(state: damus_state, evid: event.id, urls: urls)
                        Blur()
                            .disabled(true)
                    }
                    .clipShape(ChatBubbleShape(direction: isLastInGroup ? (is_ours ? ChatBubbleShape.Direction.right: ChatBubbleShape.Direction.left): ChatBubbleShape.Direction.none))
                    .contextMenu{MenuItems(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads)}
                }
                
                if !is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
            }
        }
    }

    func Invoice(invoices: [Invoice]) -> some View {
        return Group {
            HStack {
                if is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }

                InvoicesView(our_pubkey: damus_state.keypair.pubkey, invoices: invoices, settings: damus_state.settings)
                    .clipShape(ChatBubbleShape(direction: isLastInGroup ? (is_ours ? ChatBubbleShape.Direction.right: ChatBubbleShape.Direction.left): ChatBubbleShape.Direction.none))
                    .contextMenu{MenuItems(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads)}
                
                if !is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
            }
        }
    }

    func TimeStamp() -> some View {
        return Group {
            HStack {
                if is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }

                Text(format_timestamp(timestamp: event.created_at))
                    .font(.system(size: 11))
                    .font(.footnote)
                    .foregroundColor(.gray)
                
                if !is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
            }
        }
    }

    func filter_content(blocks: [Block], profiles: Profiles, privkey: String?) -> (Bool, CompatibleText?) {
        let one_note_ref = blocks
            .filter({ $0.is_note_mention })
            .count == 1
        
        var ind: Int = -1
        var show_text: Bool = false
        let txt: CompatibleText = blocks.reduce(CompatibleText()) { str, block in
            ind = ind + 1
            
            switch block {
            case .mention(let m):
                if m.type == .event && one_note_ref {
                    return str
                }
                if m.type == .pubkey {
                    show_text = true
                }
                return str + mention_str(m, profiles: profiles)
            case .text(let txt):
                var trimmed = txt
                if let prev = blocks[safe: ind-1], case .url(let u) = prev, classify_url(u).is_media != nil {
                    trimmed = " " + trim_prefix(trimmed)
                }
                
                if let next = blocks[safe: ind+1] {
                    if case .url(let u) = next, classify_url(u).is_media != nil  {
                        trimmed = trim_suffix(trimmed)
                    } else if case .mention(let m) = next, m.type == .event, one_note_ref {
                        trimmed = trim_suffix(trimmed)
                    }
                }
                if (!trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    show_text = true
                }
                return str + CompatibleText(stringLiteral: trimmed)
            case .relay(let relay):
                show_text = true
                return str + CompatibleText(stringLiteral: relay)
            case .hashtag(let htag):
                show_text = true
                return str + hashtag_str(htag)
            case .invoice:
                return str
            case .url(let url):
                if !(classify_url(url).is_media != nil) {
                    show_text = true
                    return str + url_str(url)
                } else {
                    return str
                }
            }
        }

        return (show_text, txt)
    }

    var body: some View {
        VStack {
            Mention
            DM
        }
        
    }
}

struct ChatBubbleShape: Shape {
    enum Direction {
        case left
        case right
        case none
    }
    
    let direction: Direction
    
    func path(in rect: CGRect) -> Path {
        return (direction == .none) ? getBubblePath(in: rect) : ( (direction == .left) ? getLeftBubblePath(in: rect) : getRightBubblePath(in: rect) )
    }
    
    private func getBubblePath(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let cornerRadius: CGFloat = 17
        let path = Path { p in
            p.move(to: CGPoint(x: cornerRadius, y: height))
            p.addLine(to: CGPoint(x: width - cornerRadius, y: height))
            p.addCurve(to: CGPoint(x: width, y: height - cornerRadius),
                       control1: CGPoint(x: width - cornerRadius/2, y: height),
                       control2: CGPoint(x: width, y: height - cornerRadius/2))
            p.addLine(to: CGPoint(x: width, y: cornerRadius))
            p.addCurve(to: CGPoint(x: width - cornerRadius, y: 0),
                       control1: CGPoint(x: width, y: cornerRadius/2),
                       control2: CGPoint(x: width - cornerRadius/2, y: 0))
            p.addLine(to: CGPoint(x: cornerRadius, y: 0))
            p.addCurve(to: CGPoint(x: 0, y: cornerRadius),
                       control1: CGPoint(x: cornerRadius/2, y: 0),
                       control2: CGPoint(x: 0, y: cornerRadius/2))
            p.addLine(to: CGPoint(x: 0, y: height - cornerRadius))
            p.addCurve(to: CGPoint(x: cornerRadius, y: height),
                       control1: CGPoint(x: 0, y: height - cornerRadius/2),
                       control2: CGPoint(x: cornerRadius/2, y: height))
        }
        return path
    }
    
    private func getLeftBubblePath(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let path = Path { p in
            p.move(to: CGPoint(x: 25, y: height))
            p.addLine(to: CGPoint(x: width - 20, y: height))
            p.addCurve(to: CGPoint(x: width, y: height - 20),
                       control1: CGPoint(x: width - 8, y: height),
                       control2: CGPoint(x: width, y: height - 8))
            p.addLine(to: CGPoint(x: width, y: 20))
            p.addCurve(to: CGPoint(x: width - 20, y: 0),
                       control1: CGPoint(x: width, y: 8),
                       control2: CGPoint(x: width - 8, y: 0))
            p.addLine(to: CGPoint(x: 21, y: 0))
            p.addCurve(to: CGPoint(x: 4, y: 20),
                       control1: CGPoint(x: 12, y: 0),
                       control2: CGPoint(x: 4, y: 8))
            p.addLine(to: CGPoint(x: 4, y: height - 11))
            p.addCurve(to: CGPoint(x: 0, y: height),
                       control1: CGPoint(x: 4, y: height - 1),
                       control2: CGPoint(x: 0, y: height))
            p.addLine(to: CGPoint(x: -0.05, y: height - 0.01))
            p.addCurve(to: CGPoint(x: 11.0, y: height - 4.0),
                       control1: CGPoint(x: 4.0, y: height + 0.5),
                       control2: CGPoint(x: 8, y: height - 1))
            p.addCurve(to: CGPoint(x: 25, y: height),
                       control1: CGPoint(x: 16, y: height),
                       control2: CGPoint(x: 20, y: height))
            
        }
        return path
    }
    
    private func getRightBubblePath(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let path = Path { p in
            p.move(to: CGPoint(x: 25, y: height))
            p.addLine(to: CGPoint(x:  20, y: height))
            p.addCurve(to: CGPoint(x: 0, y: height - 20),
                       control1: CGPoint(x: 8, y: height),
                       control2: CGPoint(x: 0, y: height - 8))
            p.addLine(to: CGPoint(x: 0, y: 20))
            p.addCurve(to: CGPoint(x: 20, y: 0),
                       control1: CGPoint(x: 0, y: 8),
                       control2: CGPoint(x: 8, y: 0))
            p.addLine(to: CGPoint(x: width - 21, y: 0))
            p.addCurve(to: CGPoint(x: width - 4, y: 20),
                       control1: CGPoint(x: width - 12, y: 0),
                       control2: CGPoint(x: width - 4, y: 8))
            p.addLine(to: CGPoint(x: width - 4, y: height - 11))
            p.addCurve(to: CGPoint(x: width, y: height),
                       control1: CGPoint(x: width - 4, y: height - 1),
                       control2: CGPoint(x: width, y: height))
            p.addLine(to: CGPoint(x: width + 0.05, y: height - 0.01))
            p.addCurve(to: CGPoint(x: width - 11, y: height - 4),
                       control1: CGPoint(x: width - 4, y: height + 0.5),
                       control2: CGPoint(x: width - 8, y: height - 1))
            p.addCurve(to: CGPoint(x: width - 25, y: height),
                       control1: CGPoint(x: width - 16, y: height),
                       control2: CGPoint(x: width - 20, y: height))
        }
        return path
    }
}

struct DMView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "Hey there *buddy*, want to grab some drinks later? 🍻", keypair: test_keypair, kind: 1, tags: [])!
        DMView(event: ev, damus_state: test_damus_state())
    }
}
