import CoreGraphics
import UIKit

/// Realistic demo input for "Probar con un ejemplo" and the tests: a Spanish chat with Lucía drawn
/// as one tall page and cut into four overlapping iPhone screenshots (1179 × 2556 px). Every shot
/// repeats the status bar (with a different clock), the navigation bar and the message input bar,
/// exactly like real screenshots taken while scrolling. The content is a pure vertical translation
/// of the same lossless page, so the stitcher must match every seam pixel-exactly.
enum DemoScreenshots {
    /// Pixel size of every demo screenshot (iPhone 15 Pro / 16 at 3x).
    static let screenWidth = 1179
    static let screenHeight = 2556
    /// Rows the conversation scrolls between consecutive screenshots, i.e. the expected seam
    /// offsets. With the 1956 px content viewport the overlaps are 23 %, 27 % and 22 %.
    static let scrollSteps = [1500, 1420, 1530]

    /// Realistic demo set (4 screenshots, 1179×2556 px, PNG-like/lossless, isLossy = false) cut from one
    /// tall fake chat page with status bar (clock changes between shots), navigation bar and message
    /// input bar, text drawn with real fonts, coloured bubbles, a photo, a link card and avatars.
    /// Overlaps 20–45 %.
    static func make() -> [SourceImage] {
        let width = screenWidth
        let height = screenHeight
        let viewport = height - Int(Metrics.headerHeight) - Int(Metrics.footerHeight)
        let travel = scrollSteps.reduce(0, +)
        let neededHeight = travel + viewport

        let layout = ChatLayout.make(minimumHeight: CGFloat(neededHeight))
        let contentHeight = Int(layout.height.rounded(.up))
        // Older messages scroll out above the first shot (as in a real chat). Only if the text came
        // out unexpectedly short is there blank space above the first message.
        let pageHeight = max(contentHeight, neededHeight)
        let contentTop = CGFloat(pageHeight - contentHeight)
        let blocks = layout.blocks

        let pageImage = Draw.render(width: width, height: pageHeight, { cg in
            cg.setFillColor(Palette.chatBackground.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: pageHeight))
            var y = contentTop + Metrics.topPadding
            for block in blocks {
                y += block.spacingBefore
                block.draw(cg, y)
                y += block.height
            }
        })
        guard let page = pageImage else { return [] }

        var shots: [SourceImage] = []
        var offset = pageHeight - neededHeight
        for index in 0...scrollSteps.count {
            if index > 0 {
                offset += scrollSteps[index - 1]
            }
            let visibleRect = CGRect(x: 0, y: offset, width: width, height: viewport)
            guard let visible = page.cropping(to: visibleRect) else { continue }
            let clock = "9:\(41 + index)"
            let shotImage = Draw.render(width: width, height: height, { cg in
                cg.setFillColor(Palette.chatBackground.cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
                UIImage(cgImage: visible).draw(
                    in: CGRect(x: 0, y: Int(Metrics.headerHeight), width: width, height: viewport)
                )
                Chrome.drawHeader(clock: clock, in: cg)
                Chrome.drawFooter(in: cg)
            })
            if let shot = shotImage {
                shots.append(SourceImage(cgImage: shot, isLossy: false))
            }
        }
        return shots
    }
}

// MARK: - Metrics, fonts and colours

extension DemoScreenshots {
    /// Pixel metrics of an iPhone 15 Pro screen (3x: 1 pt = 3 px).
    fileprivate enum Metrics {
        static let width: CGFloat = 1179
        static let screenHeight: CGFloat = 2556
        static let statusBarHeight: CGFloat = 162
        static let navigationBarHeight: CGFloat = 180
        static let headerHeight: CGFloat = 342
        static let inputBarHeight: CGFloat = 156
        static let footerHeight: CGFloat = 258
        static let sideMargin: CGFloat = 42
        static let avatarSize: CGFloat = 84
        /// Leading edge of incoming bubbles (room for the small avatar).
        static let incomingX: CGFloat = 144
        static let maxBubbleWidth: CGFloat = 840
        static let mediaBubbleWidth: CGFloat = 798
        static let bubblePaddingX: CGFloat = 42
        static let bubblePaddingY: CGFloat = 27
        static let bigRadius: CGFloat = 57
        static let smallRadius: CGFloat = 15
        static let mediaInset: CGFloat = 9
        static let topPadding: CGFloat = 36
        static let bottomPadding: CGFloat = 42
        static let maxTextWidth: CGFloat = 756        // maxBubbleWidth - 2 * bubblePaddingX
        static let mediaTextWidth: CGFloat = 714      // mediaBubbleWidth - 2 * bubblePaddingX
    }

    fileprivate enum Fonts {
        static let body = UIFont.systemFont(ofSize: 51)
        static let time = UIFont.systemFont(ofSize: 33)
        static let day = UIFont.systemFont(ofSize: 36, weight: .semibold)
        static let clock = UIFont.systemFont(ofSize: 51, weight: .semibold)
        static let name = UIFont.systemFont(ofSize: 51, weight: .semibold)
        static let presence = UIFont.systemFont(ofSize: 39)
        static let cardTitle = UIFont.systemFont(ofSize: 45, weight: .semibold)
        static let cardSubtitle = UIFont.systemFont(ofSize: 39)
        static let cardDomain = UIFont.systemFont(ofSize: 36, weight: .medium)
    }

    fileprivate enum Palette {
        static let chatBackground = UIColor.white
        static let bar = UIColor(red: 0.973, green: 0.973, blue: 0.98, alpha: 1)
        static let hairline = UIColor(red: 0.80, green: 0.80, blue: 0.83, alpha: 1)
        static let incomingBubble = UIColor(red: 0.914, green: 0.914, blue: 0.925, alpha: 1)
        static let primaryText = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        static let secondaryText = UIColor(red: 0.54, green: 0.54, blue: 0.57, alpha: 1)
        static let indigo = UIColor(red: 0.369, green: 0.361, blue: 0.902, alpha: 1)
        static let violet = UIColor(red: 0.749, green: 0.353, blue: 0.949, alpha: 1)
        static let dayFill = UIColor(red: 0.945, green: 0.945, blue: 0.965, alpha: 1)
        static let online = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        static let avatarTop = UIColor(red: 1.0, green: 0.64, blue: 0.43, alpha: 1)
        static let avatarBottom = UIColor(red: 0.93, green: 0.32, blue: 0.56, alpha: 1)
        static let card = UIColor(red: 0.985, green: 0.985, blue: 0.99, alpha: 1)
    }
}

// MARK: - Conversation

extension DemoScreenshots {
    fileprivate enum Sender: Equatable {
        case lucia
        case me
    }

    fileprivate enum MessageContent {
        case text(String)
        case photo(caption: String)
        case link(title: String, subtitle: String, domain: String, text: String)
    }

    fileprivate struct Message {
        let sender: Sender
        let time: String
        let content: MessageContent
    }

    fileprivate enum ChatItem {
        case day(String)
        case message(Message)

        var sender: Sender? {
            if case .message(let message) = self { return message.sender }
            return nil
        }
    }

    fileprivate enum Script {
        static func lucia(_ time: String, _ text: String) -> ChatItem {
            .message(Message(sender: .lucia, time: time, content: .text(text)))
        }

        static func me(_ time: String, _ text: String) -> ChatItem {
            .message(Message(sender: .me, time: time, content: .text(text)))
        }

        /// Yesterday's messages, oldest first. Only the most recent ones that are needed to fill
        /// the page are used (see `ChatLayout.make(minimumHeight:)`).
        static let yesterday: [ChatItem] = [
            lucia("21:38", "¿Qué tal ha ido la presentación?"),
            me("21:41", "¡Muy bien! Al final todo salió genial 😅"),
            lucia("21:42", "¡Lo sabía! Hay que celebrarlo 🎉"),
            lucia("21:47", "¿Sigue en pie lo del sábado?"),
            me("21:50", "¡Claro! Tengo muchísimas ganas de desconectar"),
            lucia("21:51", "Genial. Mañana te cuento el plan, que ahora me caigo de sueño 😴"),
            me("21:52", "Jaja vale, ¡buenas noches! 🌙")
        ]

        static let today: [ChatItem] = [
            .day("Hoy 9:12"),
            lucia("9:12", "¡Buenos días! ☀️"),
            lucia("9:12", "He estado mirando opciones para el sábado y creo que tengo el plan perfecto"),
            me("9:14", "Cuéntame, soy todo oídos 👀"),
            lucia("9:15", "Salimos temprano hacia la sierra, hacemos la ruta del mirador y bajamos a comer al pueblo"),
            lucia("9:15", "Son unos 9 km, nada muy exigente"),
            me("9:16", "Me encanta. ¿A qué hora quedamos?"),
            lucia("9:17", "¿Te va bien a las 8:30 en la estación?"),
            me("9:17", "Perfecto. Llevo el termo con café para el camino ☕️"),
            lucia("9:20", "Mira la foto que hizo mi hermana desde el mirador la semana pasada"),
            .message(Message(sender: .lucia, time: "9:20", content: .photo(caption: "Así se ve al atardecer 🌄"))),
            me("9:21", "¡Qué pasada! Parece de postal"),
            me("9:21", "Tenemos que quedarnos hasta que se ponga el sol, sí o sí"),
            me("9:24", "¿Y para comer? ¿Tienes algún sitio pensado?"),
            .message(Message(sender: .lucia, time: "9:25", content: .link(
                title: "Casa Lumbre · Cocina de montaña",
                subtitle: "Menú de temporada, brasa y terraza con vistas a la sierra.",
                domain: "casalumbre.es",
                text: "Me lo recomendó Marcos. Dicen que el cordero está increíble"
            ))),
            me("9:26", "Pinta muy bien. ¿Reservo para dos?"),
            lucia("9:27", "Mejor para cuatro, que se apuntan Marcos y Elena 🙌"),
            me("9:31", "Hecho: mesa para cuatro a las 14:30, en la terraza 😎"),
            lucia("9:32", "Yo llevo bocadillos y fruta para la subida"),
            me("9:33", "Y yo la crema solar, que la última vez acabamos como gambas 🦐"),
            lucia("9:34", "Jajaja no me lo recuerdes 😂"),
            lucia("9:38", "¡Qué ganas de que llegue el sábado!"),
            me("9:40", "¡Nos vemos a las 8:30! 🚆")
        ]
    }
}

// MARK: - Layout

extension DemoScreenshots {
    /// One vertical piece of the chat page. `draw` receives the context and the block's top y.
    fileprivate struct ChatBlock {
        let height: CGFloat
        let spacingBefore: CGFloat
        let draw: (CGContext, CGFloat) -> Void
    }

    fileprivate struct ChatPage {
        let blocks: [ChatBlock]
        /// Total height including top and bottom padding.
        let height: CGFloat
    }

    fileprivate enum ChatLayout {
        /// Today's conversation, preceded by as many of yesterday's messages as needed to make the
        /// page at least `minimumHeight` tall.
        static func make(minimumHeight: CGFloat) -> ChatPage {
            var page = layout(Script.today)
            var count = 0
            while page.height < minimumHeight && count < Script.yesterday.count {
                count += 1
                let older = Array(Script.yesterday.suffix(count))
                page = layout([ChatItem.day("Ayer")] + older + Script.today)
            }
            return page
        }

        static func layout(_ items: [ChatItem]) -> ChatPage {
            var blocks: [ChatBlock] = []
            for index in items.indices {
                let previous: ChatItem? = index > 0 ? items[index - 1] : nil
                let next: ChatItem? = index + 1 < items.count ? items[index + 1] : nil
                switch items[index] {
                case .day(let title):
                    blocks.append(dayBlock(title, spacing: previous == nil ? 0 : 54))
                case .message(let message):
                    let isFirst = previous?.sender != message.sender
                    let isLast = next?.sender != message.sender
                    let spacing: CGFloat
                    if previous == nil {
                        spacing = 0
                    } else if previous?.sender == nil {
                        spacing = 30
                    } else {
                        spacing = isFirst ? 33 : 9
                    }
                    blocks.append(messageBlock(message, isFirst: isFirst, isLast: isLast, spacing: spacing))
                }
            }
            let height = blocks.reduce(Metrics.topPadding + Metrics.bottomPadding) {
                $0 + $1.spacingBefore + $1.height
            }
            return ChatPage(blocks: blocks, height: height)
        }

        static func messageBlock(_ message: Message, isFirst: Bool, isLast: Bool, spacing: CGFloat) -> ChatBlock {
            switch message.content {
            case .text(let text):
                return textBlock(text, message: message, isFirst: isFirst, isLast: isLast, spacing: spacing)
            case .photo(let caption):
                return photoBlock(caption: caption, message: message, isFirst: isFirst, isLast: isLast, spacing: spacing)
            case .link(let title, let subtitle, let domain, let text):
                return linkBlock(
                    title: title, subtitle: subtitle, domain: domain, text: text,
                    message: message, isFirst: isFirst, isLast: isLast, spacing: spacing
                )
            }
        }

        // MARK: Blocks

        static func dayBlock(_ title: String, spacing: CGFloat) -> ChatBlock {
            let label = Draw.attributed(title, font: Fonts.day, color: Palette.secondaryText)
            let size = Draw.measure(label, maxWidth: 900)
            let capsuleWidth = size.width + 48
            let capsuleHeight = size.height + 24
            return ChatBlock(height: capsuleHeight, spacingBefore: spacing) { cg, top in
                let x = ((Metrics.width - capsuleWidth) / 2).rounded()
                let capsule = CGRect(x: x, y: top, width: capsuleWidth, height: capsuleHeight)
                Draw.fill(Draw.roundedRect(capsule, radius: capsuleHeight / 2), Palette.dayFill, in: cg)
                Draw.text(label, at: CGPoint(x: x + 24, y: top + 12), width: size.width + 4)
            }
        }

        static func textBlock(_ text: String, message: Message, isFirst: Bool, isLast: Bool, spacing: CGFloat) -> ChatBlock {
            let outgoing = message.sender == .me
            let body = bodyText(text, time: message.time, outgoing: outgoing)
            let size = Draw.measure(body, maxWidth: Metrics.maxTextWidth)
            let bubbleWidth = size.width + 2 * Metrics.bubblePaddingX
            let bubbleHeight = size.height + 2 * Metrics.bubblePaddingY
            return ChatBlock(height: bubbleHeight, spacingBefore: spacing) { cg, top in
                let x = outgoing ? Metrics.width - Metrics.sideMargin - bubbleWidth : Metrics.incomingX
                let bubble = CGRect(x: x, y: top, width: bubbleWidth, height: bubbleHeight)
                ChatLayout.drawBubble(bubble, outgoing: outgoing, isFirst: isFirst, isLast: isLast, in: cg)
                let textTop = top + Metrics.bubblePaddingY
                Draw.text(body, at: CGPoint(x: x + Metrics.bubblePaddingX, y: textTop), width: Metrics.maxTextWidth)
                ChatLayout.drawTime(
                    message.time, outgoing: outgoing,
                    right: bubble.maxX - Metrics.bubblePaddingX, bottom: textTop + size.height, in: cg
                )
                if !outgoing && isLast {
                    ChatLayout.drawSmallAvatar(besideBubble: bubble, in: cg)
                }
            }
        }

        static func photoBlock(caption: String, message: Message, isFirst: Bool, isLast: Bool, spacing: CGFloat) -> ChatBlock {
            let outgoing = message.sender == .me
            let width = Metrics.mediaBubbleWidth
            let inset = Metrics.mediaInset
            let photoHeight: CGFloat = 570
            let body = bodyText(caption, time: message.time, outgoing: outgoing)
            let size = Draw.measure(body, maxWidth: Metrics.mediaTextWidth)
            let height = inset + photoHeight + 24 + size.height + Metrics.bubblePaddingY
            return ChatBlock(height: height, spacingBefore: spacing) { cg, top in
                let x = outgoing ? Metrics.width - Metrics.sideMargin - width : Metrics.incomingX
                let bubble = CGRect(x: x, y: top, width: width, height: height)
                ChatLayout.drawBubble(bubble, outgoing: outgoing, isFirst: isFirst, isLast: isLast, in: cg)
                let photo = CGRect(x: x + inset, y: top + inset, width: width - 2 * inset, height: photoHeight)
                let clip = ChatLayout.mediaPath(photo, outgoing: outgoing, isFirst: isFirst)
                Artwork.drawLandscape(in: photo, clip: clip, context: cg)
                let textTop = photo.maxY + 24
                Draw.text(body, at: CGPoint(x: x + Metrics.bubblePaddingX, y: textTop), width: Metrics.mediaTextWidth)
                ChatLayout.drawTime(
                    message.time, outgoing: outgoing,
                    right: bubble.maxX - Metrics.bubblePaddingX, bottom: textTop + size.height, in: cg
                )
                if !outgoing && isLast {
                    ChatLayout.drawSmallAvatar(besideBubble: bubble, in: cg)
                }
            }
        }

        static func linkBlock(
            title: String, subtitle: String, domain: String, text: String,
            message: Message, isFirst: Bool, isLast: Bool, spacing: CGFloat
        ) -> ChatBlock {
            let outgoing = message.sender == .me
            let width = Metrics.mediaBubbleWidth
            let inset = Metrics.mediaInset
            let cardWidth = width - 2 * inset
            let previewHeight: CGFloat = 345
            let metaPadding: CGFloat = 30
            let metaWidth = cardWidth - 2 * metaPadding

            let titleText = Draw.attributed(title, font: Fonts.cardTitle, color: Palette.primaryText)
            let subtitleText = Draw.attributed(subtitle, font: Fonts.cardSubtitle, color: Palette.secondaryText)
            let domainText = Draw.attributed(domain, font: Fonts.cardDomain, color: Palette.indigo)
            let titleSize = Draw.measure(titleText, maxWidth: metaWidth)
            let subtitleSize = Draw.measure(subtitleText, maxWidth: metaWidth)
            let domainSize = Draw.measure(domainText, maxWidth: metaWidth)
            let metaHeight = titleSize.height + 6 + subtitleSize.height + 12 + domainSize.height
            let cardHeight = previewHeight + 2 * metaPadding + metaHeight

            let body = bodyText(text, time: message.time, outgoing: outgoing)
            let size = Draw.measure(body, maxWidth: Metrics.mediaTextWidth)
            let height = inset + cardHeight + 24 + size.height + Metrics.bubblePaddingY

            return ChatBlock(height: height, spacingBefore: spacing) { cg, top in
                let x = outgoing ? Metrics.width - Metrics.sideMargin - width : Metrics.incomingX
                let bubble = CGRect(x: x, y: top, width: width, height: height)
                ChatLayout.drawBubble(bubble, outgoing: outgoing, isFirst: isFirst, isLast: isLast, in: cg)

                let card = CGRect(x: x + inset, y: top + inset, width: cardWidth, height: cardHeight)
                let cardPath = ChatLayout.mediaPath(card, outgoing: outgoing, isFirst: isFirst)
                Draw.fill(cardPath, Palette.card, in: cg)
                let preview = CGRect(x: card.minX, y: card.minY, width: cardWidth, height: previewHeight)
                Artwork.drawDish(in: preview, clip: cardPath, context: cg)

                var y = preview.maxY + metaPadding
                let metaX = card.minX + metaPadding
                Draw.text(titleText, at: CGPoint(x: metaX, y: y), width: metaWidth)
                y += titleSize.height + 6
                Draw.text(subtitleText, at: CGPoint(x: metaX, y: y), width: metaWidth)
                y += subtitleSize.height + 12
                Draw.text(domainText, at: CGPoint(x: metaX, y: y), width: metaWidth)

                let textTop = card.maxY + 24
                Draw.text(body, at: CGPoint(x: x + Metrics.bubblePaddingX, y: textTop), width: Metrics.mediaTextWidth)
                ChatLayout.drawTime(
                    message.time, outgoing: outgoing,
                    right: bubble.maxX - Metrics.bubblePaddingX, bottom: textTop + size.height, in: cg
                )
                if !outgoing && isLast {
                    ChatLayout.drawSmallAvatar(besideBubble: bubble, in: cg)
                }
            }
        }

        // MARK: Pieces

        /// Message text followed by an invisible copy of the time: the visible time drawn at the
        /// bubble's bottom-right corner then never overlaps the last line of text.
        static func bodyText(_ text: String, time: String, outgoing: Bool) -> NSAttributedString {
            let color = outgoing ? UIColor.white : Palette.primaryText
            let result = NSMutableAttributedString(
                attributedString: Draw.attributed(text, font: Fonts.body, color: color)
            )
            // Figure spaces (non-breaking) keep room for the read receipt next to the time.
            let reserve = "  " + time + (outgoing ? "\u{2007}\u{2007}\u{2007}" : "")
            result.append(Draw.attributed(reserve, font: Fonts.time, color: .clear))
            return result
        }

        /// Messenger-style corners: tighter on the side where consecutive bubbles of a group meet.
        static func drawBubble(_ rect: CGRect, outgoing: Bool, isFirst: Bool, isLast: Bool, in cg: CGContext) {
            let big = Metrics.bigRadius
            let small = Metrics.smallRadius
            if outgoing {
                let path = Draw.roundedRect(
                    rect, topLeft: big, topRight: isFirst ? big : small,
                    bottomRight: isLast ? big : small, bottomLeft: big
                )
                Draw.fill(
                    path, gradient: Draw.gradient([Palette.indigo, Palette.violet]),
                    from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY), in: cg
                )
            } else {
                let path = Draw.roundedRect(
                    rect, topLeft: isFirst ? big : small, topRight: big,
                    bottomRight: big, bottomLeft: isLast ? big : small
                )
                Draw.fill(path, Palette.incomingBubble, in: cg)
            }
        }

        /// Rounded shape of a photo or link card inset inside its bubble.
        static func mediaPath(_ rect: CGRect, outgoing: Bool, isFirst: Bool) -> CGPath {
            let outer = Metrics.bigRadius - Metrics.mediaInset
            let inner = max(Metrics.smallRadius - Metrics.mediaInset, 4)
            let bottom: CGFloat = 12
            if outgoing {
                return Draw.roundedRect(
                    rect, topLeft: outer, topRight: isFirst ? outer : inner,
                    bottomRight: bottom, bottomLeft: bottom
                )
            }
            return Draw.roundedRect(
                rect, topLeft: isFirst ? outer : inner, topRight: outer,
                bottomRight: bottom, bottomLeft: bottom
            )
        }

        static func drawTime(_ time: String, outgoing: Bool, right: CGFloat, bottom: CGFloat, in cg: CGContext) {
            let color = outgoing ? UIColor.white.withAlphaComponent(0.8) : Palette.secondaryText
            let label = Draw.attributed(time, font: Fonts.time, color: color)
            let size = Draw.measure(label, maxWidth: 300)
            let receiptWidth: CGFloat = outgoing ? 48 : 0
            let origin = CGPoint(x: right - receiptWidth - size.width, y: bottom - size.height)
            Draw.text(label, at: origin, width: size.width + 4)
            if outgoing {
                drawReadReceipt(
                    at: CGPoint(x: right - receiptWidth + 9, y: bottom - size.height / 2 - 10),
                    color: color, in: cg
                )
            }
        }

        /// Two check marks ("read").
        static func drawReadReceipt(at origin: CGPoint, color: UIColor, in cg: CGContext) {
            cg.saveGState()
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(4)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for dx: CGFloat in [0, 14] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: origin.x + dx, y: origin.y + 10))
                path.addLine(to: CGPoint(x: origin.x + dx + 8, y: origin.y + 18))
                path.addLine(to: CGPoint(x: origin.x + dx + 24, y: origin.y))
                cg.addPath(path)
            }
            cg.strokePath()
            cg.restoreGState()
        }

        static func drawSmallAvatar(besideBubble bubble: CGRect, in cg: CGContext) {
            let size = Metrics.avatarSize
            let rect = CGRect(x: Metrics.sideMargin, y: bubble.maxY - size, width: size, height: size)
            drawAvatar(in: rect, fontSize: 39, context: cg)
        }

        /// Gradient circle with Lucía's initial.
        static func drawAvatar(in rect: CGRect, fontSize: CGFloat, context cg: CGContext) {
            Draw.fill(
                CGPath(ellipseIn: rect, transform: nil),
                gradient: Draw.gradient([Palette.avatarTop, Palette.avatarBottom]),
                from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY), in: cg
            )
            let initial = Draw.attributed("L", font: UIFont.systemFont(ofSize: fontSize, weight: .semibold), color: .white)
            let size = Draw.measure(initial, maxWidth: rect.width)
            Draw.text(
                initial,
                at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                width: size.width + 4
            )
        }
    }
}

// MARK: - Fixed bars

extension DemoScreenshots {
    /// Status bar + navigation bar (top) and message input bar + home indicator (bottom). They are
    /// drawn identically on every shot except for the clock, like real screenshots.
    fileprivate enum Chrome {
        static func drawHeader(clock: String, in cg: CGContext) {
            cg.setFillColor(Palette.bar.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: Metrics.width, height: Metrics.headerHeight))
            cg.setFillColor(Palette.hairline.cgColor)
            cg.fill(CGRect(x: 0, y: Metrics.headerHeight - 1, width: Metrics.width, height: 1))
            drawStatusBar(clock: clock, in: cg)
            drawNavigationBar(in: cg)
        }

        static func drawStatusBar(clock: String, in cg: CGContext) {
            let centerY: CGFloat = 88

            let time = Draw.attributed(clock, font: Fonts.clock, color: .black)
            let timeSize = Draw.measure(time, maxWidth: 400)
            Draw.text(
                time,
                at: CGPoint(x: (192 - timeSize.width / 2).rounded(), y: (centerY - timeSize.height / 2).rounded()),
                width: timeSize.width + 4
            )

            // Cellular signal.
            let barHeights: [CGFloat] = [15, 21, 28, 35]
            for (index, barHeight) in barHeights.enumerated() {
                let bar = CGRect(x: 846 + CGFloat(index) * 16, y: centerY + 17 - barHeight, width: 10, height: barHeight)
                Draw.fill(Draw.roundedRect(bar, radius: 3), .black, in: cg)
            }

            Draw.symbol("wifi", center: CGPoint(x: 954, y: centerY), pointSize: 42, weight: .semibold, color: .black)

            // Battery.
            let body = CGRect(x: 997, y: centerY - 19, width: 78, height: 38)
            cg.saveGState()
            cg.addPath(Draw.roundedRect(body.insetBy(dx: 1.5, dy: 1.5), radius: 11))
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(3)
            cg.strokePath()
            cg.restoreGState()
            let level = CGRect(x: body.minX + 6, y: body.minY + 6, width: (body.width - 12) * 0.8, height: body.height - 12)
            Draw.fill(Draw.roundedRect(level, radius: 6), .black, in: cg)
            let nub = CGRect(x: body.maxX + 3, y: centerY - 7, width: 5, height: 14)
            Draw.fill(Draw.roundedRect(nub, radius: 2.5), UIColor.black.withAlphaComponent(0.4), in: cg)
        }

        static func drawNavigationBar(in cg: CGContext) {
            let centerY = Metrics.statusBarHeight + Metrics.navigationBarHeight / 2

            Draw.symbol("chevron.left", center: CGPoint(x: 66, y: centerY), pointSize: 60, weight: .semibold, color: Palette.indigo)

            let avatar = CGRect(x: 114, y: centerY - 54, width: 108, height: 108)
            ChatLayout.drawAvatar(in: avatar, fontSize: 51, context: cg)
            let dot = CGRect(x: avatar.maxX - 30, y: avatar.maxY - 30, width: 30, height: 30)
            Draw.fill(CGPath(ellipseIn: dot.insetBy(dx: -5, dy: -5), transform: nil), Palette.bar, in: cg)
            Draw.fill(CGPath(ellipseIn: dot, transform: nil), Palette.online, in: cg)

            let name = Draw.attributed("Lucía", font: Fonts.name, color: Palette.primaryText)
            let presence = Draw.attributed("en línea", font: Fonts.presence, color: Palette.secondaryText)
            let nameSize = Draw.measure(name, maxWidth: 600)
            let presenceSize = Draw.measure(presence, maxWidth: 600)
            let top = (centerY - (nameSize.height + presenceSize.height) / 2).rounded()
            Draw.text(name, at: CGPoint(x: 252, y: top), width: nameSize.width + 4)
            Draw.text(presence, at: CGPoint(x: 252, y: top + nameSize.height), width: presenceSize.width + 4)

            Draw.symbol("video", center: CGPoint(x: 978, y: centerY), pointSize: 54, weight: .regular, color: Palette.indigo)
            Draw.symbol("phone", center: CGPoint(x: 1101, y: centerY), pointSize: 51, weight: .regular, color: Palette.indigo)
        }

        static func drawFooter(in cg: CGContext) {
            let top = Metrics.screenHeight - Metrics.footerHeight
            cg.setFillColor(Palette.bar.cgColor)
            cg.fill(CGRect(x: 0, y: top, width: Metrics.width, height: Metrics.footerHeight))
            cg.setFillColor(Palette.hairline.cgColor)
            cg.fill(CGRect(x: 0, y: top, width: Metrics.width, height: 1))

            let centerY = top + Metrics.inputBarHeight / 2
            Draw.symbol("plus", center: CGPoint(x: 84, y: centerY), pointSize: 63, weight: .regular, color: Palette.indigo)

            let field = CGRect(x: 147, y: centerY - 54, width: 798, height: 108)
            let fieldPath = Draw.roundedRect(field, radius: 54)
            Draw.fill(fieldPath, .white, in: cg)
            cg.saveGState()
            cg.addPath(Draw.roundedRect(field.insetBy(dx: 1.5, dy: 1.5), radius: 52.5))
            cg.setStrokeColor(Palette.hairline.cgColor)
            cg.setLineWidth(3)
            cg.strokePath()
            cg.restoreGState()

            let placeholder = Draw.attributed("Mensaje", font: Fonts.body, color: Palette.secondaryText)
            let placeholderSize = Draw.measure(placeholder, maxWidth: 600)
            Draw.text(
                placeholder,
                at: CGPoint(x: field.minX + 42, y: (centerY - placeholderSize.height / 2).rounded()),
                width: placeholderSize.width + 4
            )
            Draw.symbol("face.smiling", center: CGPoint(x: field.maxX - 57, y: centerY), pointSize: 48, weight: .regular, color: Palette.secondaryText)

            Draw.symbol("camera", center: CGPoint(x: 1014, y: centerY), pointSize: 54, weight: .regular, color: Palette.indigo)
            Draw.symbol("mic", center: CGPoint(x: 1110, y: centerY), pointSize: 54, weight: .regular, color: Palette.indigo)

            let indicator = CGRect(x: 388, y: Metrics.screenHeight - 39, width: 402, height: 15)
            Draw.fill(Draw.roundedRect(indicator, radius: 7.5), .black, in: cg)
        }
    }
}

// MARK: - Illustrations

extension DemoScreenshots {
    fileprivate enum Artwork {
        /// Sunset over layered mountains (the photo Lucía sends).
        static func drawLandscape(in rect: CGRect, clip: CGPath, context cg: CGContext) {
            cg.saveGState()
            cg.addPath(clip)
            cg.clip()

            let sky = Draw.gradient(
                [
                    UIColor(red: 0.16, green: 0.12, blue: 0.42, alpha: 1),
                    UIColor(red: 0.58, green: 0.26, blue: 0.62, alpha: 1),
                    UIColor(red: 0.98, green: 0.46, blue: 0.47, alpha: 1),
                    UIColor(red: 1.00, green: 0.77, blue: 0.48, alpha: 1)
                ],
                locations: [0, 0.38, 0.7, 1]
            )
            if let sky {
                cg.drawLinearGradient(
                    sky,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.72),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            let stars: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
                (0.07, 0.08, 4), (0.19, 0.18, 3), (0.31, 0.06, 5), (0.44, 0.15, 3), (0.58, 0.05, 4),
                (0.74, 0.11, 3), (0.88, 0.07, 5), (0.94, 0.22, 3), (0.13, 0.31, 3), (0.52, 0.27, 3)
            ]
            for star in stars {
                let center = point(in: rect, star.x, star.y)
                let dotRect = CGRect(x: center.x - star.r, y: center.y - star.r, width: star.r * 2, height: star.r * 2)
                Draw.fill(CGPath(ellipseIn: dotRect, transform: nil), UIColor.white.withAlphaComponent(0.85), in: cg)
            }

            let sun = point(in: rect, 0.66, 0.55)
            if let glow = Draw.gradient([
                UIColor(red: 1.0, green: 0.86, blue: 0.56, alpha: 0.8),
                UIColor(red: 1.0, green: 0.62, blue: 0.5, alpha: 0)
            ]) {
                cg.drawRadialGradient(glow, startCenter: sun, startRadius: 50, endCenter: sun, endRadius: 270, options: [])
            }
            let sunRect = CGRect(x: sun.x - 66, y: sun.y - 66, width: 132, height: 132)
            Draw.fill(CGPath(ellipseIn: sunRect, transform: nil), UIColor(red: 1.0, green: 0.94, blue: 0.74, alpha: 1), in: cg)

            // Birds.
            cg.saveGState()
            cg.setStrokeColor(UIColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 0.7).cgColor)
            cg.setLineWidth(4)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let birds: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [(0.30, 0.36, 18), (0.36, 0.31, 14), (0.41, 0.38, 12)]
            for bird in birds {
                let c = point(in: rect, bird.x, bird.y)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: c.x - bird.s, y: c.y - bird.s * 0.5))
                path.addQuadCurve(to: c, control: CGPoint(x: c.x - bird.s * 0.5, y: c.y - bird.s * 0.7))
                path.addQuadCurve(to: CGPoint(x: c.x + bird.s, y: c.y - bird.s * 0.5), control: CGPoint(x: c.x + bird.s * 0.5, y: c.y - bird.s * 0.7))
                cg.addPath(path)
            }
            cg.strokePath()
            cg.restoreGState()

            let far: [(CGFloat, CGFloat)] = [
                (0, 0.63), (0.1, 0.5), (0.2, 0.58), (0.33, 0.42), (0.47, 0.57), (0.6, 0.48),
                (0.73, 0.6), (0.86, 0.45), (1, 0.58), (1, 1), (0, 1)
            ]
            let middle: [(CGFloat, CGFloat)] = [
                (0, 0.74), (0.14, 0.62), (0.29, 0.71), (0.44, 0.6), (0.6, 0.73), (0.77, 0.63),
                (1, 0.75), (1, 1), (0, 1)
            ]
            let near: [(CGFloat, CGFloat)] = [
                (0, 0.87), (0.18, 0.79), (0.38, 0.85), (0.57, 0.77), (0.79, 0.86), (1, 0.8), (1, 1), (0, 1)
            ]
            Draw.fill(Draw.polygon(far.map { point(in: rect, $0.0, $0.1) }), UIColor(red: 0.56, green: 0.31, blue: 0.6, alpha: 1), in: cg)
            Draw.fill(Draw.polygon(middle.map { point(in: rect, $0.0, $0.1) }), UIColor(red: 0.36, green: 0.18, blue: 0.46, alpha: 1), in: cg)
            Draw.fill(Draw.polygon(near.map { point(in: rect, $0.0, $0.1) }), UIColor(red: 0.17, green: 0.1, blue: 0.27, alpha: 1), in: cg)

            // Pine trees on the nearest hill.
            let pineColor = UIColor(red: 0.1, green: 0.06, blue: 0.17, alpha: 1)
            let pines: [(x: CGFloat, h: CGFloat)] = [(0.08, 70), (0.13, 52), (0.66, 64), (0.71, 84), (0.76, 58), (0.9, 66)]
            for pine in pines {
                let base = point(in: rect, pine.x, 0.86)
                let tree = Draw.polygon([
                    CGPoint(x: base.x, y: base.y - pine.h),
                    CGPoint(x: base.x + pine.h * 0.3, y: base.y),
                    CGPoint(x: base.x - pine.h * 0.3, y: base.y)
                ])
                Draw.fill(tree, pineColor, in: cg)
            }

            cg.restoreGState()
        }

        /// Stylised dish for the restaurant link preview.
        static func drawDish(in rect: CGRect, clip: CGPath, context cg: CGContext) {
            cg.saveGState()
            cg.addPath(clip)
            cg.clip()
            cg.clip(to: rect)

            let background = Draw.gradient([
                UIColor(red: 1.0, green: 0.74, blue: 0.38, alpha: 1),
                UIColor(red: 0.95, green: 0.40, blue: 0.33, alpha: 1)
            ])
            if let background {
                cg.drawLinearGradient(
                    background,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.maxX, y: rect.maxY),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            let soft = UIColor.white.withAlphaComponent(0.13)
            Draw.fill(CGPath(ellipseIn: CGRect(x: rect.minX - 90, y: rect.minY - 110, width: 300, height: 300), transform: nil), soft, in: cg)
            Draw.fill(CGPath(ellipseIn: CGRect(x: rect.maxX - 230, y: rect.maxY - 150, width: 360, height: 360), transform: nil), soft, in: cg)

            let center = CGPoint(x: rect.midX, y: rect.midY)
            func circle(_ dx: CGFloat, _ dy: CGFloat, _ radius: CGFloat) -> CGPath {
                CGPath(ellipseIn: CGRect(x: center.x + dx - radius, y: center.y + dy - radius, width: radius * 2, height: radius * 2), transform: nil)
            }

            // Plate with shadow.
            Draw.fill(circle(0, 12, 124), UIColor.black.withAlphaComponent(0.12), in: cg)
            Draw.fill(circle(0, 0, 122), UIColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 1), in: cg)
            Draw.fill(circle(0, 0, 94), UIColor(red: 0.97, green: 0.93, blue: 0.88, alpha: 1), in: cg)

            // Food.
            let tomato = UIColor(red: 0.89, green: 0.26, blue: 0.21, alpha: 1)
            let basil = UIColor(red: 0.30, green: 0.64, blue: 0.30, alpha: 1)
            let yolk = UIColor(red: 1.0, green: 0.80, blue: 0.27, alpha: 1)
            Draw.fill(circle(-34, -22, 27), tomato, in: cg)
            Draw.fill(circle(30, 28, 25), tomato, in: cg)
            Draw.fill(circle(38, -36, 21), tomato, in: cg)
            Draw.fill(circle(-6, 8, 18), yolk, in: cg)
            Draw.fill(circle(-44, 34, 14), yolk, in: cg)
            for leaf in [CGRect(x: -20, y: -58, width: 40, height: 20), CGRect(x: -70, y: 4, width: 36, height: 18),
                         CGRect(x: 48, y: -4, width: 38, height: 19), CGRect(x: -8, y: 46, width: 34, height: 17)] {
                let leafRect = leaf.offsetBy(dx: center.x, dy: center.y)
                Draw.fill(CGPath(ellipseIn: leafRect, transform: nil), basil, in: cg)
            }

            // Cutlery.
            let cutlery = UIColor.white.withAlphaComponent(0.92)
            let knife = CGRect(x: center.x + 168, y: center.y - 100, width: 20, height: 200)
            Draw.fill(Draw.roundedRect(knife, radius: 10), cutlery, in: cg)
            let forkHandle = CGRect(x: center.x - 186, y: center.y - 30, width: 16, height: 130)
            Draw.fill(Draw.roundedRect(forkHandle, radius: 8), cutlery, in: cg)
            let forkHead = CGRect(x: center.x - 198, y: center.y - 50, width: 40, height: 30)
            Draw.fill(Draw.roundedRect(forkHead, radius: 10), cutlery, in: cg)
            for tine in 0..<3 {
                let tineRect = CGRect(x: center.x - 198 + CGFloat(tine) * 15, y: center.y - 100, width: 10, height: 60)
                Draw.fill(Draw.roundedRect(tineRect, radius: 5), cutlery, in: cg)
            }

            cg.restoreGState()
        }

        static func point(in rect: CGRect, _ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * fy)
        }
    }
}

// MARK: - Drawing helpers

extension DemoScreenshots {
    fileprivate enum Draw {
        /// Opaque 8-bit sRGB bitmap of exactly `width` × `height` pixels (scale 1).
        static func render(width: Int, height: Int, _ actions: @escaping (CGContext) -> Void) -> CGImage? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            format.preferredRange = .standard
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            let image = renderer.image { context in
                actions(context.cgContext)
            }
            return image.cgImage
        }

        static func attributed(_ string: String, font: UIFont, color: UIColor) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.alignment = .left
            return NSAttributedString(string: string, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ])
        }

        /// Size of wrapped text, rounded up to whole pixels.
        static func measure(_ text: NSAttributedString, maxWidth: CGFloat) -> CGSize {
            let bounds = text.boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        }

        /// Draws wrapped text with the options used by `measure`; pass the same width as the
        /// measurement so lines break identically.
        static func text(_ text: NSAttributedString, at origin: CGPoint, width: CGFloat) {
            text.draw(
                with: CGRect(x: origin.x, y: origin.y, width: width, height: 4000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }

        static func roundedRect(
            _ rect: CGRect, topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat
        ) -> CGPath {
            let limit = max(0, min(rect.width, rect.height) / 2)
            let tl = min(topLeft, limit)
            let tr = min(topRight, limit)
            let br = min(bottomRight, limit)
            let bl = min(bottomLeft, limit)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: tr)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: br)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: bl)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: tl)
            path.closeSubpath()
            return path
        }

        static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
            roundedRect(rect, topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
        }

        static func polygon(_ points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            return path
        }

        static func fill(_ path: CGPath, _ color: UIColor, in cg: CGContext) {
            cg.addPath(path)
            cg.setFillColor(color.cgColor)
            cg.fillPath()
        }

        static func fill(_ path: CGPath, gradient: CGGradient?, from start: CGPoint, to end: CGPoint, in cg: CGContext) {
            guard let gradient else { return }
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            cg.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            cg.restoreGState()
        }

        static func gradient(_ colors: [UIColor], locations: [CGFloat]? = nil) -> CGGradient? {
            let colorList: [CGColor] = colors.map { $0.cgColor }
            let cgColors = colorList as CFArray
            let space = CGColorSpace(name: CGColorSpace.sRGB)
            if let locations {
                return CGGradient(colorsSpace: space, colors: cgColors, locations: locations)
            }
            return CGGradient(colorsSpace: space, colors: cgColors, locations: nil)
        }

        /// SF Symbol tinted and centred on `center` (its point size is in pixels here).
        static func symbol(_ name: String, center: CGPoint, pointSize: CGFloat, weight: UIImage.SymbolWeight, color: UIColor) {
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            guard let image = UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
            let size = image.size
            image.draw(in: CGRect(
                x: (center.x - size.width / 2).rounded(),
                y: (center.y - size.height / 2).rounded(),
                width: size.width,
                height: size.height
            ))
        }
    }
}
