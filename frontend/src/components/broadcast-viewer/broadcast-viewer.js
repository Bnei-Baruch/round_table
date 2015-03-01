/* jshint strict:false */

(function () {
  Polymer({
    webRtcEndpointId: null,
    assignMasterEndpoint: function (e, message) {
      if (message.role === this.role &&
          message.webRtcEndpointId !== this.webRtcEndpointId) {
        this.webRtcEndpointId = message.endpointId;
        this.initKurento();
      }
    },
    register: function () {
      this.$.signaling.sendMessage({action: 'register-viewer'});
    },
    initKurento: function () {
      var that = this;

      this.shutdown();

      this.webRtcPeer = kurentoUtils.WebRtcPeer.startRecvOnly(
        that.$.mediaElement, function (sdpOffer) {
          kurentoClient(that.$.config.kurentoWsUri, that.cancelOnError(function(error, kurentoClient) {
            that.kurentoClient = kurentoClient;

            kurentoClient.getMediaobjectById(that.webRtcEndpointId, that.cancelOnError(function(error, webRtcEndpoint) {

              webRtcEndpoint.getMediaPipeline(that.cancelOnError(function(error, pipeline) {

                pipeline.create('WebRtcEndpoint', that.cancelOnError(function(error, viewerEndpoint){

                  that.viewerEndpoint = viewerEndpoint;

                  webRtcEndpoint.connect(viewerEndpoint, that.cancelOnError(function(){
                    console.log('Connected to master');
                  }));

                  viewerEndpoint.processOffer(sdpOffer, that.cancelOnError(function(error, sdpAnswer){
                    that.webRtcPeer.processSdpAnswer(sdpAnswer);
                  }));

                }));
              }));
            }));
          }));
        }, this.onError);
    }
  });

})();
