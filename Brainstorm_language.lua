local lovely = require("lovely")
local nativefs = require("nativefs")

function Brainstorm.BU()
    return nativefs.read(lovely.mod_dir .. "/Brainstorm/Language/BU.lua")
end

function Game:set_language()
    if not self.LANGUAGES then 
        if not (love.filesystem.read('localization/'..G.SETTINGS.language..'.lua')) and not (Brainstorm.BU()) or G.F_ENGLISH_ONLY then
            ------------------------------------------
            --SET LANGUAGE FOR FIRST TIME STARTUP HERE

            ------------------------------------------

            G.SETTINGS.language = 'en-us'
        end
        -------------------------------------------------------
        --IF LANGUAGE NEEDS TO BE SET ON EVERY REBOOT, SET HERE

        -------------------------------------------------------

        self.LANGUAGES = {
            ['en-us'] = {font = 1, label = "English", key = 'en-us', button = "Language Feedback", warning = {'This language is still in Beta. To help us','improve it, please click on the feedback button.', 'Click again to confirm'}},
            ['BU'] = {font = 1, label = "Balatro University", key = 'BU', beta = nil, button = "Language Feedback", warning = {'This language is still in Beta.', 'Click again to confirm'}},
            ['de'] = {font = 1, label = "Deutsch", key = 'de', beta = nil, button = "Feedback zur Übersetzung", warning = {'Diese Übersetzung ist noch im Beta-Stadium. Willst du uns helfen,','sie zu verbessern? Dann klicke bitte auf die Feedback-Taste.', "Zum Bestätigen erneut klicken"}},
            ['es_419'] = {font = 1, label = "Español (México)", key = 'es_419', beta = nil, button = "Sugerencias de idioma", warning = {'Este idioma todavía está en Beta. Pulsa el botón','de sugerencias para ayudarnos a mejorarlo.', "Haz clic de nuevo para confirmar"}},
            ['es_ES'] = {font = 1, label = "Español (España)", key = 'es_ES', beta = nil, button = "Sugerencias de idioma", warning = {'Este idioma todavía está en Beta. Pulsa el botón','de sugerencias para ayudarnos a mejorarlo.', "Haz clic de nuevo para confirmar"}},
            ['fr'] = {font = 1, label = "Français", key = 'fr', beta = nil, button = "Partager votre avis", warning = {'La traduction française est encore en version bêta. ','Veuillez cliquer sur le bouton pour nous donner votre avis.', "Cliquez à nouveau pour confirmer"}},
            ['id'] = {font = 1, label = "Bahasa Indonesia", key = 'id', beta = true, button = "Umpan Balik Bahasa", warning = {'Bahasa ini masih dalam tahap Beta. Untuk membantu','kami meningkatkannya, silakan klik tombol umpan balik.', "Klik lagi untuk mengonfirmasi"}},
            ['it'] = {font = 1, label = "Italiano", key = 'it', beta = nil, button = "Feedback traduzione", warning = {'Questa traduzione è ancora in Beta. Per','aiutarci a migliorarla, clicca il tasto feedback', "Fai clic di nuovo per confermare"}},
            ['ja'] = {font = 5, label = "日本語", key = 'ja', beta = nil, button = "提案する", warning = {'この翻訳は現在ベータ版です。提案があった場合、','ボタンをクリックしてください。', "もう一度クリックして確認"}},
            ['ko'] = {font = 4, label = "한국어", key = 'ko', beta = true, button = "번역 피드백", warning = {'이 언어는 아직 베타 단계에 있습니다. ','번역을 도와주시려면 피드백 버튼을 눌러주세요.', "다시 클릭해서 확인하세요"}},
            ['nl'] = {font = 1, label = "Nederlands", key = 'nl', beta = nil, button = "Taal suggesties", warning = {'Deze taal is nog in de Beta fase. Help ons het te ','verbeteren door op de suggestie knop te klikken.', "Klik opnieuw om te bevestigen"}},
            ['pl'] = {font = 1, label = "Polski", key = 'pl', beta = nil, button = "Wyślij uwagi do tłumaczenia", warning = {'Polska wersja językowa jest w fazie Beta. By pomóc nam poprawić',' jakość tłumaczenia, kliknij przycisk i podziel się swoją opinią i uwagami.', "Kliknij ponownie, aby potwierdzić"}},
            ['pt_BR'] = {font = 1, label = "Português", key = 'pt_BR', beta = nil, button = "Feedback de Tradução", warning = {'Esta tradução ainda está em Beta. Se quiser nos ajudar','a melhorá-la, clique no botão de feedback por favor', "Clique novamente para confirmar"}},
            ['ru'] = {font = 6, label = "Русский", key = 'ru', beta = true, button = "Отзыв о языке", warning = {'Этот язык все еще находится в Бета-версии. Чтобы помочь','нам его улучшить, пожалуйста, нажмите на кнопку обратной связи.', "Щелкните снова, чтобы подтвердить"}},
            ['zh_CN'] = {font = 2, label = "简体中文", key = 'zh_CN', beta = nil, button = "意见反馈", warning = {'这个语言目前尚为Beta版本。 请帮助我们改善翻译品质，','点击”意见反馈” 来提供你的意见。', "再次点击确认"}},
            ['zh_TW'] = {font = 3, label = "繁體中文", key = 'zh_TW', beta = nil, button = "意見回饋", warning = {'這個語言目前尚為Beta版本。請幫助我們改善翻譯品質，','點擊”意見回饋” 來提供你的意見。', "再按一下即可確認"}},
            ['all1'] = {font = 8, label = "English", key = 'all', omit = true},
            ['all2'] = {font = 9, label = "English", key = 'all', omit = true},
        }
        --if G.F_ENGLISH_ONLY then
        --    self.LANGUAGES = {
        --        ['en-us'] = self.LANGUAGES['en-us']
        --    }
        --end
        
        --load the font and set filter
        self.FONTS = {
            {file = "resources/fonts/m6x11plus.ttf", render_scale = self.TILESIZE*10, TEXT_HEIGHT_SCALE = 0.83, TEXT_OFFSET = {x=10,y=-20}, FONTSCALE = 0.1, squish = 1, DESCSCALE = 1},
            {file = "resources/fonts/NotoSansSC-Bold.ttf", render_scale = self.TILESIZE*7, TEXT_HEIGHT_SCALE = 0.7, TEXT_OFFSET = {x=0,y=-35}, FONTSCALE = 0.12, squish = 1, DESCSCALE = 1.1},
            {file = "resources/fonts/NotoSansTC-Bold.ttf", render_scale = self.TILESIZE*7, TEXT_HEIGHT_SCALE = 0.7, TEXT_OFFSET = {x=0,y=-35}, FONTSCALE = 0.12, squish = 1, DESCSCALE = 1.1},
            {file = "resources/fonts/NotoSansKR-Bold.ttf", render_scale = self.TILESIZE*7, TEXT_HEIGHT_SCALE = 0.8, TEXT_OFFSET = {x=0,y=-20}, FONTSCALE = 0.12, squish = 1, DESCSCALE = 1},
            {file = "resources/fonts/NotoSansJP-Bold.ttf", render_scale = self.TILESIZE*7, TEXT_HEIGHT_SCALE = 0.8, TEXT_OFFSET = {x=0,y=-20}, FONTSCALE = 0.12, squish = 1, DESCSCALE = 1},
            {file = "resources/fonts/NotoSans-Bold.ttf", render_scale = self.TILESIZE*7, TEXT_HEIGHT_SCALE = 0.65, TEXT_OFFSET = {x=0,y=-40}, FONTSCALE = 0.12, squish = 1, DESCSCALE = 1},
            {file = "resources/fonts/m6x11plus.ttf", render_scale = self.TILESIZE*10, TEXT_HEIGHT_SCALE = 0.9, TEXT_OFFSET = {x=10,y=15}, FONTSCALE = 0.1, squish = 1, DESCSCALE = 1},
            {file = "resources/fonts/GoNotoCurrent-Bold.ttf", render_scale = self.TILESIZE*10, TEXT_HEIGHT_SCALE = 0.8, TEXT_OFFSET = {x=10,y=-20}, FONTSCALE = 0.1, squish = 1, DESCSCALE = 1},
            {file = "resources/fonts/GoNotoCJKCore.ttf", render_scale = self.TILESIZE*10, TEXT_HEIGHT_SCALE = 0.8, TEXT_OFFSET = {x=10,y=-20}, FONTSCALE = 0.1, squish = 1, DESCSCALE = 1},
        }
        for _, v in ipairs(self.FONTS) do
            if love.filesystem.getInfo(v.file) then 
                v.FONT = love.graphics.newFont( v.file, v.render_scale)
            end
        end
        for _, v in pairs(self.LANGUAGES) do
            v.font = self.FONTS[v.font]
        end
    end

    self.LANG = self.LANGUAGES[self.SETTINGS.language] or self.LANGUAGES['en-us']

    local localization = love.filesystem.getInfo('localization/'..G.SETTINGS.language..'.lua')
    if G.SETTINGS.language == 'BU' then
        self.localization = assert(loadstring(Brainstorm.BU()))()
        init_localization()
    end
    if localization ~= nil and G.SETTINGS.language ~= "BU" then
      self.localization = assert(loadstring(love.filesystem.read('localization/'..G.SETTINGS.language..'.lua')))()
      init_localization()
    end
end