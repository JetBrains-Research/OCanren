open GT
open MiniKanren
open Std

@type 'nat move = Forward of 'nat | Backward of 'nat | Unload of 'nat | Fill of 'nat with show, gmap
                                                                                                  
module M = Fmap (struct type 'a t = 'a move let fmap f = gmap(move) f end)

let show_move  m = show(logic) (show(move) (show(LNat.logic))) m
let show_moves m = show(LList.logic) show_move m

let reify_moves m = LList.reify (M.reify LNat.reify) m

let forward  x = inj @@ M.distrib (Forward  x)
let backward x = inj @@ M.distrib (Backward x)
let unload   x = inj @@ M.distrib (Unload   x)
let fill     x = inj @@ M.distrib (Fill     x)                                  

let rec lookupo d stations q =
  conde [
    stations === nil () &&& (q === none ());
    fresh (d' q' ss) (
      stations === (pair d' q') % ss &&&
      ((d' === d &&& (some q' === q)) |||
       (LNat.(<) d' d &&& lookupo d ss q) |||
       (LNat.(>) d' d &&& (q === none ()))
      )    
    )
  ]

let notZero n = fresh (x) (n === LNat.succ x)
                      
let rec puto stations d q stations' =
  conde [
    stations === nil () &&& conde [q === LNat.zero &&& (stations' === nil ()); notZero q &&& (stations' === !< (pair d q))];
    fresh (d' q' ss ss') (
      stations === (pair d' q') % ss &&&
      ((d' === d &&& conde [q === LNat.zero &&& (stations' === ss); notZero q &&& (stations' === (pair d q) % ss)]) |||
       (LNat.(<) d' d &&& puto ss d q ss' &&& (stations' === (pair d' q') % ss')) |||
       (LNat.(>) d' d &&& conde [q === LNat.zero &&& (stations' === stations); notZero q &&& (stations' === (pair d q) % stations)])
      )    
    )
  ]

let triple a b c = pair a @@ pair b c
                                  
let show_stations s = show(LList.logic) (show(LPair.logic) (show(LNat.logic)) (show(LNat.logic))) s
let reify_stations s = LList.reify (LPair.reify LNat.reify LNat.reify) s

let show_state s = show(LPair.logic) (show(LNat.logic)) (show(LPair.logic) (show(LNat.logic)) show_stations) s
let reify_state s = LPair.reify LNat.reify (LPair.reify LNat.reify reify_stations) s

let max_capacity = nat 5
                     
let step state m state' =
  fresh (pos gas stations) (
    state === triple pos gas stations &&&
    conde [
      fresh (d pos' gas') (m === forward  d &&& (state' === triple pos' gas' stations) &&& LNat.(<=) d gas &&& LNat.addo pos d pos' &&& LNat.addo gas' d gas);
      fresh (d pos' gas') (m === backward d &&& (state' === triple pos' gas' stations) &&& LNat.(<=) d gas &&& LNat.addo pos' d pos &&& LNat.addo gas' d gas);
      fresh (q gas' stations') (          
        m === unload q &&& LNat.(<=) q max_capacity &&& (state' === triple pos gas' stations') &&& LNat.(<=) q gas &&& LNat.addo q gas' gas &&&
        ((lookupo pos stations (none ()) &&& puto stations pos q stations') |||
         fresh (q' q'') (
           lookupo pos stations (some q') &&& (LNat.addo q' q q'' &&& puto stations pos q'' stations')
         )
        ) 
      );
      fresh (q gas' q' q'' stations') (
        m === fill q &&& LNat.(<=) q max_capacity &&&
        conde [
          pos === LNat.zero &&&
          (state' === triple pos gas' stations) &&&
          LNat.addo gas q gas' &&&
          LNat.(<=) gas' max_capacity;
          notZero pos &&&
          (state' === triple pos gas' stations') &&&
          lookupo pos stations (some q') &&& 
          LNat.(>=) q' q &&&
          LNat.addo gas q gas' &&&
          LNat.(<=) gas' max_capacity &&&
          LNat.addo q'' q q' &&&
          puto stations pos q'' stations'
        ]
      ) 
    ]    
  )
                
let rec inj_moves = function
| []      -> nil ()
| h :: tl -> (match h with Forward n -> forward @@ nat n | Backward n -> backward @@ nat n | Fill n -> fill @@ nat n | Unload n -> unload @@ nat n) % inj_moves tl

let kind m k =
  fresh (n) (
    conde [
      (m === forward n ||| (m === backward n)) &&& (n =/= LNat.zero) &&& (k === !!0);
      (m === fill    n ||| (m === unload   n)) &&& (n =/= LNat.zero) &&& (k === !!1);
    ]
  )

let steps state moves state' =
  let steps = Tabling.(tabledrec four) (fun steps k state moves state' ->
    conde [
      moves === nil () &&& (state === state');
      fresh (state'' m moves' k') (
        moves === m % moves' &&&
        kind m k' &&&
        (k' =/= k) &&&  
        (step state m state'' &&&
        steps k' state'' moves' state')
      )
    ])
  in
  steps !!2 state moves state'

let init = triple (nat 0) max_capacity (nil ())
let id x = x
             
let _ =
  List.iter (fun q -> Printf.printf "Reaching 6: %s\n%!" (show_state (q#reify reify_state))) @@ RStream.take ~n:1 @@
  run q (fun q -> steps init (inj_moves [Forward 2; Unload 1; Backward 2; Fill 5; Forward 2; Fill 1; Forward 4]) q) id;
        
  List.iter (fun q -> Printf.printf "Making stations: %s\n%!" (show_state (q#reify reify_state))) @@ RStream.take ~n:1 @@
  run q (fun q -> steps init (inj_moves [Forward 1; Unload 2; Backward 1; Fill 3; Forward 2]) q) id;
  
  List.iter (fun q -> Printf.printf "Searching for making stations: %s\n%!" (show_moves (q#reify reify_moves))) @@ RStream.take ~n:1 @@
  run q (fun q -> steps init q (triple (nat 2) (nat 2) (!< (pair (nat 1) (nat 2))))) id;

  List.iter (fun q -> Printf.printf "Searching for reaching 6: %s\n%!" (show_moves (q#reify reify_moves))) @@ RStream.take ~n:1 @@
  run q (fun q -> steps init q (triple (nat 6) (nat 0) (nil ()))) id;

  List.iter (fun q -> Printf.printf "Reaching 8: %s\n%!" (show_state (q#reify reify_state))) @@ RStream.take ~n:1 @@
  run q (fun q -> steps init (inj_moves [Forward 2; Unload 1; Backward 2; Fill 3; Forward 1; Unload 1; Backward 1; 
                                         Fill 5; Forward 2; Unload 1; Backward 2; Fill 5; Forward 1; 
                                         Fill 1; Forward 1; Fill 1; Forward 1; Unload 2; Backward 1; Fill 1; Backward 2; 
                                         Fill 3; Forward 1; Unload 1; Backward 1; Fill 5; Forward 1; Fill 1; 
                                         Forward 2; Fill 2; Forward 5]) q) id;

  List.iter (fun q -> Printf.printf "Searching for reaching 8: %s\n%!" (show_moves (q#reify reify_moves))) @@ RStream.take ~n:1 @@
  run q (fun q -> fresh (r s) (steps init q (triple (nat 8) r s))) id;
