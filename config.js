// Generated by LiveScript 1.5.0
(function(){
  module.exports = function(System){
    return System.config({
      map: {
        three: './three.js/build/three.js'
      },
      meta: {
        '*.ls': {
          loader: 'system-livescript'
        },
        '*.html': {
          loader: 'system-text'
        },
        '*/cannon.js': {
          format: 'cjs'
        }
      }
    });
  };
}).call(this);
