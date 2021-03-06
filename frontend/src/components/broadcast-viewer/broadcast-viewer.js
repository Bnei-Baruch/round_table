/* jshint strict:false */

(function () {
  Polymer({
    webRtcEndpointId: null,
    assignMasterEndpoint: function (e, message) {
      // Assign if the endpoint matches viewer
      if (message.role === this.role &&
          (message.language === this.language || (this.role === 'instructor')) &&
          message.webRtcEndpointId !== this.webRtcEndpointId) {
        console.debug("Assigning", message.role, "endpoint");
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
                that.createEndpoint(sdpOffer, webRtcEndpoint, pipeline);
              }));
            }));
          }));
        }, this.onError);
    },
    createEndpoint: function (sdpOffer, webRtcEndpoint, pipeline) {
      var that = this;

      pipeline.create('WebRtcEndpoint', that.cancelOnError(function(error, viewerEndpoint){

        that.viewerEndpoint = viewerEndpoint;
        that.registerForRelease(viewerEndpoint);

        webRtcEndpoint.connect(viewerEndpoint, that.cancelOnError(function(){
          console.log('Connected to master');
        }));

        viewerEndpoint.processOffer(sdpOffer, that.cancelOnError(function(error, sdpAnswer){
          that.webRtcPeer.processSdpAnswer(sdpAnswer);
          that.fire('master-connected');
        }));

      }));
    },
    toggleAudio: function (enabled) {
      this.$.mediaElement.muted = !enabled;
    }
  });

})();
