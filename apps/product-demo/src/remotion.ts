import {registerRoot} from 'remotion';
import React from 'react';
import {RemotionRoot} from './Film';
import {VoicePromoRoot} from './voice-promo/VoicePromo';
registerRoot(()=>React.createElement(React.Fragment,null,React.createElement(RemotionRoot),React.createElement(VoicePromoRoot)));
