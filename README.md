# Magnus – Diario di allenamento per iOS

App iOS (SwiftUI + SwiftData) per caricare la foto della propria scheda di palestra e
segnare, giorno per giorno, i pesi usati per ogni esercizio, con grafici di progressione.

Palette: nero, azzurro scuro e rosso.

## Cosa fa

- **Scheda da foto**: scatti o scegli la foto della scheda. Il testo viene letto sul telefono
  (framework Vision, nessun server) e trasformato in giorni ed esercizi con serie × ripetizioni
  e recupero. Funziona con le tabelle tipo ESERCIZIO | SERIE | REC. | KG: i blocchi separati da
  una riga vuota diventano Giorno A / Giorno B, il recupero scritto una sola volta vale per le
  righe successive, e le righe a tempo (5 min riscaldamento, 10 min corsa, cyclette) diventano
  esercizi "a tempo". Prima di salvare controlli e correggi tutto.
- **Gruppi muscolari**: ogni esercizio viene assegnato automaticamente a un gruppo (Petto,
  Schiena, Spalle, Bicipiti, Tricipiti, Gambe, Glutei, Addome, Cardio) e puoi cambiarlo. Serve a
  confrontare schede diverse nel tempo: "Chest press" e "Pectoral machine" finiscono entrambi in
  Petto.
- **Storico unico tra le schede**: ogni serie registrata ricorda nome esercizio e gruppo
  muscolare. Cambiare o eliminare una scheda non cancella nulla; lo stesso esercizio su schede
  diverse viene unito nello stesso grafico, e i pesi dell'ultima volta vengono ripresi anche se
  arrivano da una scheda precedente.
- **Scheda manuale**: in alternativa crei giorni ed esercizi a mano.
- **Recuperi fissi**: il tempo di recupero scritto sulla scheda resta fisso; durante
  l'allenamento non si modifica e viene usato dal timer di recupero che parte quando spunti
  una serie.
- **Allenamento**: scegli il giorno (A, B, C…), per ogni esercizio segni kg e ripetizioni serie
  per serie. I pesi sono precompilati con quelli dell'ultima volta, con i tasti ±2,5 kg.
  Se hai completato tutte le serie con le ripetizioni massime, l'app suggerisce il nuovo peso.
  Se superi il tuo record compare il badge "Nuovo record".
- **Peso obiettivo**: per ogni esercizio puoi impostare il peso che vuoi raggiungere; lo vedi
  come linea tratteggiata nel grafico e come barra di avanzamento.
- **Progressi**: allenamenti totali, settimana corrente, serie negli ultimi 30 giorni, settimane
  consecutive, calendario a "mattonelle" degli ultimi 4 mesi, allenamenti per settimana, confronto
  per gruppo muscolare (volume settimanale ed elenco esercizi con ultimo peso, massimo e
  variazione) e grafico per esercizio (peso massimo o volume per allenamento), unito tra tutte le
  schede.
- **Storico**: tutti gli allenamenti terminati, mese per mese, con i gruppi muscolari allenati,
  filtro per gruppo e dettaglio delle serie.

## Requisiti

- Xcode 16 o successivo (il progetto usa le cartelle sincronizzate di Xcode 16).
- iOS 17.0 o successivo.
- Per la fotocamera serve un iPhone reale; nel simulatore si usa la galleria.

## Come aprirla

1. Apri `Magnus.xcodeproj` con Xcode.
2. In *Signing & Capabilities* seleziona il tuo Team (account Apple gratuito sufficiente per
   installarla sul tuo iPhone).
3. Scegli il tuo iPhone come destinazione e premi Run.

## Struttura del progetto

```
Magnus/
├── MagnusApp.swift            # entry point, container SwiftData
├── Models/
│   ├── Models.swift           # WorkoutPlan, WorkoutDay, Exercise, WorkoutSession, SetLog
│   ├── MuscleGroup.swift      # gruppi muscolari e classificazione automatica dal nome
│   └── ExerciseHistory.swift  # storico unito per nome esercizio e gruppo, serie per i grafici
├── Theme/Theme.swift          # palette e stili riutilizzabili
├── Services/
│   ├── PlanOCRService.swift   # lettura foto (Vision) + parsing di esercizi/serie/recuperi
│   └── Utilities.swift        # regex, parser dei recuperi, ridimensionamento immagini
└── Views/
    ├── ContentView.swift      # tab bar
    ├── Plan/                  # scheda attiva, editor esercizi, elenco schede
    ├── Import/                # importazione da foto e revisione di ciò che è stato letto
    ├── Workout/               # scelta giorno, registrazione serie, timer di recupero
    ├── Progress/              # statistiche, calendario e grafici (Swift Charts)
    └── History/               # storico allenamenti
```

## Formati riconosciuti nella foto

- Serie × ripetizioni: `4x10`, `4 x 8-12`, `3×12`, `4 serie da 10`
- Recupero: `90''`, `90"`, `1'30`, `2'`, `2 min`, `rec 90`, `recupero: 1'30`
- Righe a tempo: `5 min riscaldamento`, `10 min corsa`, `Cyclette 10 min`
- Giorni: `Giorno A`, `Day 1`, `Scheda B`, `Lunedì`, `Push` / `Pull` / `Legs`, oppure blocchi
  separati da una riga vuota (o da una nuova riga di riscaldamento)

Tutto ciò che non viene riconosciuto si corregge nella schermata di controllo prima del salvataggio.
